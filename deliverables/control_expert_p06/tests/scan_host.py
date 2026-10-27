"""Selected ST section execution on host. NOT a Control Expert runtime.
Uses the repository's explicit ST-subset translator and extends scalar calls,
TON/TOF/R_TRIG/FB_DelayOn used by these sections. DT is a fixed test clock.
TIME is seconds; no PLC memory layout, EBOOL edge semantics or hardware model.
"""
from pathlib import Path
from copy import deepcopy
import re, sys, xml.etree.ElementTree as ET
from blark.parse import parse_source_code
import st_scan_base as st

old_expr, old_statements = st.expr, st.statements


def name(node):
    return str(st.children(node)[0])


def parameters(node):
    args, outputs = [], []
    for p in st.children(node)[1:]:
        c = st.children(p)
        if p.data == 'output_parameter_assignment':
            outputs.append((name(c[0]), st.expr(c[-1])))
        elif p.data == 'param_assignment':
            args.append((name(c[0]) if len(c) > 1 else '', st.expr(c[-1])))
        else:
            raise NotImplementedError(p.data)
    return args, outputs


def expression(node):
    if getattr(node, 'data', None) == 'hex_integer':
        return str(int(str(st.children(node)[0]).replace('_', ''), 16))
    if getattr(node, 'data', None) == 'direct_variable':
        return f'v[{"".join(str(x) for x in st.children(node))!r}]'
    if getattr(node, 'data', None) == 'function_call':
        args, outputs = parameters(node)
        assert not outputs
        return 'scalar(' + repr(name(st.children(node)[0])) + ', [' + ','.join(x[1] for x in args) + '])'
    return old_expr(node)


def statements(node, indent=0):
    if getattr(node, 'data', None) == 'function_call':
        c = st.children(node)
        args, outputs = parameters(node)
        callargs = '{' + ','.join(repr(k) + ':' + v for k, v in args) + '}'
        block = name(c[0])
        pad = '    ' * indent
        out = pad + f'call(v, {block!r}, {callargs}, dt)\n'
        for field, target in outputs:
            out += pad + target + ' = v[' + repr(block) + '][' + repr(field) + ']\n'
        return out
    return old_statements(node, indent)


st.expr, st.statements = expression, statements


def scalar(fn, values):
    if fn in ('MAX', 'MAX_REAL'): return max(values)
    if fn in ('MIN', 'MIN_REAL'): return min(values)
    if fn == 'LIMIT': return max(values[0], min(values[1], values[2]))
    if fn in ('ABS', 'ABS_REAL'): return abs(values[0])
    if fn == 'DINT_TO_TIME': return values[0] / 1000.
    if fn in ('INT_TO_REAL', 'DINT_TO_REAL'): return float(values[0])
    if fn in ('INT_TO_DINT', 'DINT_TO_INT', 'REAL_TO_INT', 'REAL_TO_DINT'): return int(round(values[0]))
    if fn == 'BCD_TO_INT':
        x = values[0]
        return (x & 15) + 10 * ((x >> 4) & 15) + 100 * ((x >> 8) & 15) + 1000 * ((x >> 12) & 15)
    if fn == 'DT_TO_ARINT': return {0: 0, 1: 0x1200, 2: 0x1027, 3: 0x2026}
    raise NotImplementedError(fn)


def call(v, block, args, dt):
    timer = v.setdefault(block, {})
    if block == 'RRTC_DT':
        timer['OUT'] = 0
    elif 'Condition' in args:
        # Existing FC_Condition DFB: discrete SEC_P counting, not wall-clock TON.
        count = timer.get('Condition_Delay', 0)
        if args['Condition']:
            if count < args['SP_Condition_Delay'] and args['SEC_P']: count += 1
            timer['Condition_OK'] = count >= args['SP_Condition_Delay']
        else:
            count = 0; timer['Condition_OK'] = False
        timer['Condition_Delay'] = count
    elif 'CLK' in args:
        timer['Q'] = bool(args['CLK']) and not timer.get('old', False)
        timer['old'] = bool(args['CLK'])
    else:
        timer.setdefault('Q', False); timer.setdefault('ET', 0.); timer.setdefault('active', False)
        signal = bool(args['IN'])
        preset = args.get('PT', args.get('PT_S'))
        if v.get('__types', {}).get(block) == 'TOF':
            if signal:
                timer.update(Q=True, ET=0., active=False)
            elif timer['Q']:
                timer['ET'] = timer['ET'] + dt if timer['active'] else 0.
                timer['active'] = True
                if timer['ET'] >= preset: timer['Q'] = False
        else:
            st.ton(timer, signal, preset, dt)


class Host:
    cache = {}

    def __init__(self, key, sections):
        base = Path(__file__).resolve().parents[1]
        r = ET.parse(base / (key + '-source.xml')).getroot()
        self.v = {'__types': {}}
        for node in r.findall('./dataBlock/variables'):
            n, t = node.get('name'), node.get('typeName')
            self.v['__types'][n] = t
            a = re.fullmatch(r'ARRAY\s*\[\s*(-?\d+)\.\.(-?\d+)\s*\]\s*OF\s*(\w+)', t)
            if a:
                value = {i: False if a[3] in ('BOOL','EBOOL') else 0 for i in range(int(a[1]),int(a[2])+1)}
            elif t in ('BOOL', 'EBOOL'): value = False
            elif t in ('INT','DINT','UINT','WORD','DWORD','REAL','TIME','DT'): value = 0
            else: value = {}
            self.v[n] = value
        codes = []
        for section in sections:
            source = next(p.find('STSource').text for p in r.findall('program')
                          if p.find('identProgram').get('name') == section)
            cache_key = (key, section, source)
            if cache_key not in self.cache:
                parsed = parse_source_code(source, starting_rule='statement_list')
                if parsed.exception: raise parsed.exception
                self.cache[cache_key] = compile(st.statements(parsed.tree), section, 'exec')
            codes.append(self.cache[cache_key])
        self.codes = codes

    def scan(self, dt=1., **inputs):
        self.v.update(inputs)
        for code in self.codes:
            exec(code, dict(v=self.v, dt=dt, call=call, scalar=scalar))
        return self.v

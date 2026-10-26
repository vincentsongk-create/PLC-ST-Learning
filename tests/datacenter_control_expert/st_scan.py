"""Host-only execution of the ST subset used by this example, via blark's AST.

Not a Schneider compiler or PLC simulator. TIME uses seconds; REAL uses Python
float; TON uses scan time with an initial false-to-true scan at ET=0. All boolean
operands are evaluated. Unknown syntax fails rather than silently being ignored.
Only use on trusted repository source (generated Python is executed).
"""
from copy import deepcopy
from pathlib import Path
from lark import Token, Tree
from blark.parse import parse_source_code


def children(node):
    return [x for x in node.children if x is not None]


def expr(node):
    if isinstance(node, Token):
        return str(node)
    c = children(node)
    k = str(node.data)
    if k == 'variable_name':
        return f'v[{str(c[0])!r}]'
    if k == 'multi_element_variable':
        result = expr(c[0])
        for selector in c[1:]:
            if selector.data == 'subscript_list':
                result += '[' + expr(children(selector)[0]) + ']'
            elif selector.data == 'field_selector':
                name = str(children(children(selector)[0])[0])
                result += f'[{name!r}]'
            else:
                raise NotImplementedError(selector.data)
        return result
    if k in ('integer', 'real_literal'):
        return str(c[-1])
    if k in ('true', 'false'):
        return 'True' if k == 'true' else 'False'
    if k == 'duration':
        factors = {'days': 86400, 'hours': 3600, 'minutes': 60,
                   'seconds': 1, 'milliseconds': .001}
        return repr(sum(float(str(children(x)[0])) * factors[str(x.data)] for x in c))
    if k == 'unary_expression':
        if len(c) == 1:
            return expr(c[0])
        return '(' + ('not ' if str(c[0]) == 'NOT' else str(c[0])) + expr(c[1]) + ')'
    if len(c) == 1:
        return expr(c[0])
    if k.endswith('_expression') or k == 'expression_term':
        result = expr(c[0])
        ops = {'AND': '&', 'OR': '|', 'XOR': '^', '=': '==', '<>': '!='}
        for i in range(1, len(c), 2):
            op = str(c[i])
            result = '(' + result + ' ' + ops.get(op, op) + ' ' + expr(c[i + 1]) + ')'
        return result
    raise NotImplementedError((k, c))


def statements(node, indent=0):
    c = children(node)
    k = str(node.data)
    pad = '    ' * indent
    if k in ('statement_list', 'case_element_statement_list'):
        return ''.join(statements(x, indent) for x in c) or pad + 'pass\n'
    if k == 'assignment_statement':
        return pad + expr(c[0]) + ' = ' + expr(c[-1]) + '\n'
    if k == 'if_statement':
        out = pad + 'if ' + expr(c[0]) + ':\n' + statements(c[1], indent + 1)
        for clause in c[2:]:
            p = children(clause)
            if clause.data == 'else_if_clause':
                out += pad + 'elif ' + expr(p[0]) + ':\n' + statements(p[1], indent + 1)
            elif clause.data == 'else_clause':
                out += pad + 'else:\n' + statements(p[0], indent + 1)
            else:
                raise NotImplementedError(clause.data)
        return out
    if k == 'for_statement':
        if len(c) != 4:
            raise NotImplementedError('FOR BY')
        return (pad + 'for ' + expr(c[0]) + ' in range(int(' + expr(c[1])
                + '), int(' + expr(c[2]) + ') + 1):\n' + statements(c[-1], indent + 1))
    if k == 'case_statement':
        out = pad + '_case_value = ' + expr(c[0]) + '\n'
        for index, element in enumerate(children(c[1])):
            labels, body = children(element)
            values = ', '.join(expr(x) for x in children(labels))
            out += (pad + ('if ' if index == 0 else 'elif ')
                    + '_case_value in (' + values + ',):\n' + statements(body, indent + 1))
        if len(c) > 2:
            out += pad + 'else:\n' + statements(children(c[2])[0], indent + 1)
        return out
    if k == 'function_call_statement':
        return statements(c[0], indent)
    if k == 'function_call':
        args = {}
        for arg in c[1:]:
            name, value = children(arg)
            args[str(children(name)[0])] = expr(value)
        return (pad + 'ton(' + expr(c[0]) + ', ' + args['IN'] + ', '
                + args['PT'] + ', dt)\n')
    raise NotImplementedError(k)


def ton(timer, signal, preset, dt):
    if not signal:
        timer.update(Q=False, ET=0.0, active=False)
    else:
        timer['ET'] = min(preset, timer['ET'] + dt) if timer['active'] else 0.0
        timer['active'] = True
        timer['Q'] = timer['ET'] >= preset


STATUS = dict(Available=False, Ready=False, Loaded=False, ChillerRunning=False,
              Starting=False, Stopping=False, CanStop=False, Fault=False,
              State=0, FaultCode=0)


class Block:
    cache = {}

    def __init__(self, filename):
        if filename in self.cache:
            defaults, self.code = self.cache[filename]
            self.v = deepcopy(defaults)
            return
        source = Path(__file__).resolve().parents[2] / 'examples/datacenter_control_expert' / filename
        parsed = parse_source_code(source.read_text(), fn=source)
        if parsed.exception:
            raise parsed.exception
        block = children(parsed.tree)[0]
        self.v = {}
        defaults = {'BOOL': False, 'INT': 0, 'REAL': 0.0, 'TIME': 0.0,
                    'TON': dict(Q=False, ET=0.0, active=False),
                    'T_DC_TrainStatus': STATUS,
                    'T_DC_StatusArray': {i: deepcopy(STATUS) for i in range(1, 17)},
                    'T_DC_BoolArray': {i: False for i in range(1, 17)},
                    'T_DC_HoursArray': {i: 0.0 for i in range(1, 17)}}
        for decl in block.find_data('var1_init_decl'):
            names, spec = children(decl)
            parts = children(spec)
            typename = str(children(parts[0])[0])
            value = deepcopy(defaults[typename])
            if len(parts) > 1:
                value = eval(expr(parts[1]), {'v': self.v})
            for name in names.find_data('variable_name'):
                self.v[str(children(name)[0])] = deepcopy(value)
        body = next(x for x in children(block) if isinstance(x, Tree) and x.data == 'statement_list')
        self.code = compile(statements(body), str(source), 'exec')
        self.cache[filename] = (deepcopy(self.v), self.code)

    def scan(self, dt=1.0, **inputs):
        self.v.update(inputs)
        exec(self.code, {'v': self.v, 'ton': ton, 'dt': dt})
        return self.v

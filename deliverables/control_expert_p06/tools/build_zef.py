"""Rebuild user-provided P05 ZEF archives, preserving hardware and other members.
Usage: python3 tools/build_zef.py /path/CHP01-P05.ZEF /path/SMCL-P05.ZEF
No Control Expert compilation is performed. Output props explicitly says unbuilt.
"""
from pathlib import Path
import sys, re, zipfile, hashlib, json
import xml.etree.ElementTree as ET

BASE = Path(__file__).resolve().parents[1]
ROOTS = {}
ORIGINALS = {}


def load(path, key):
    with zipfile.ZipFile(path) as z:
        r = ET.fromstring(z.read('unitpro.xef'))
    ROOTS[key] = r
    ORIGINALS[key] = Path(path)
    return r


def section(key, name):
    for p in ROOTS[key].findall('program'):
        if p.find('identProgram').get('name') == name:
            return p.find('STSource')
    raise KeyError((key, name))


def change(key, name, text):
    section(key, name).text = text


def replace(key, name, old, new):
    node = section(key, name)
    if old not in node.text:
        raise ValueError((key, name, old))
    node.text = node.text.replace(old, new)


def add_section(key, name, after, text):
    r = ROOTS[key]
    existing = next(p for p in r.findall('program') if p.find('identProgram').get('name') == after)
    number = int(existing.find('identProgram').get('SectionOrder')) + 1
    for p in r.findall('program'):
        ident = p.find('identProgram')
        if ident.get('type') == 'section' and int(ident.get('SectionOrder')) >= number:
            ident.set('SectionOrder', str(int(ident.get('SectionOrder')) + 1))
    p = ET.Element('program')
    ET.SubElement(p, 'identProgram', name=name, type='section', task='MAST', SectionOrder=str(number))
    ET.SubElement(p, 'STSource').text = text
    r.insert(list(r).index(existing) + 1, p)


def variables(key, overrides, located):
    r = ROOTS[key]
    data = r.find('dataBlock')
    known = {v.get('name') for v in data.findall('variables')}
    source = '\n'.join(n.text or '' for n in r.iter('STSource'))
    source = re.sub(r'\(\*.*?\*\)', '', source, flags=re.S)
    names = set(re.findall(r'\bP06_[A-Za-z0-9_]+\b', source)) | set(located)
    timers = set(re.findall(r'\b(P06_\w+)\s*\(\s*IN\s*:=', source))
    new = []
    for name in sorted(names):
        if name in known:
            raise ValueError('P06 collision: ' + name)
        kind = overrides.get(name, 'TON' if name in timers else 'BOOL')
        node = ET.SubElement(data, 'variables', name=name, typeName=kind)
        if name in located:
            node.set('topologicalAddress', located[name])
        ET.SubElement(node, 'comment').text = 'P06 rewritten control; see delivery notes. Not commissioned.'
        new.append(dict(name=name, type=kind, address=located.get(name)))
    return new


def build(chp, smcl):
    load(chp, 'CHP01'); load(smcl, 'SMCL')
    boot = '''(* P06 boot/reset capture must precede Main/UNIT_FAULT. *)
P06_Boot := NOT P06_InitDone OR %S0 OR %S1;
P06_InitDone := TRUE;
P06_LocalReset := UNIT_Reset;
'''
    change('CHP01', 'INIT', boot + section('CHP01', 'INIT').text)
    for name in ['Chiller_Start', 'Chiller_Stop']:
        change('CHP01', name, (BASE / 'sources/CHP01' / (name + '.st')).read_text())
    replace('CHP01', 'UNIT_FAULT', 'OR CH_MS OR TST_NOCAP);',
        'OR CH_MS OR TST_MS OR TST_NOCAP OR P06_SeqFault OR P06_ConfigFault OR LOCAL_EN);')
    replace('CHP01', 'IF_RX', 'IF Network_Main THEN',
        'IF Network_Main AND ((RX1_BITS AND 16#0020) <> 0) THEN')
    replace('CHP01', 'IF_RX', 'ELSIF Network_Stby THEN',
        'ELSIF Network_Stby AND ((RX2_BITS AND 16#0020) <> 0) THEN')
    change('CHP01', 'IF_RX', section('CHP01', 'IF_RX').text + '\nP06_ChemGrant := SMCL_COMM_OK AND NOT LOCAL_EN AND ((RX_BITS AND 16#0040) <> 0);\n')
    # Remove reset pulses on loss of authority; never replay a stale reset.
    replace('CHP01', 'IF_RX', 'IF LOCAL_EN THEN',
        'SMCL_RESET := FALSE;\nIF LOCAL_EN THEN')
    # Existing dedicated secondary-line read was left pointed at the primary.
    for p in ROOTS['CHP01'].findall('program'):
        if p.find('identProgram').get('name') == 'Main':
            for block in p.iter('FFBBlock'):
                if block.get('instanceName') == '.2' and block.get('typeName') == 'READ_VAR':
                    pin = next(x for x in block.iter('inputVariable') if x.get('formalParameter') == 'ADR')
                    assert '10.54.18.134' in pin.get('effectiveParameter')
                    pin.set('effectiveParameter', pin.get('effectiveParameter').replace('10.54.18.134', '10.54.18.135'))
    replace('CHP01', 'OUT_ARB', 'IF CH_MS THEN\n    V1 := 0.0;',
        'IF P06_Isolatable THEN\n    V1 := 0.0;')
    replace('CHP01', 'OUT_ARB', 'ELSIF TST_MS THEN',
        '''ELSIF (P06_State >= 50) AND (P06_State <= 70) THEN
    (* Keep the last proven lineup through actual stop and pump post-run. *)
    V1 := CHV01_Auto_OP; V2 := CHV02_Auto_OP;
    V3 := CHV03_Auto_OP; VB := CHBPV_Auto_OP;
ELSIF TST_MS AND NOT ACH_RUN AND NOT CHP_RUN THEN''')
    replace('CHP01', 'OUT_ARB', 'AND (NOT CH_MS);\nACH_Auto_OP := START_ACH_REQ AND (NOT CH_MS);',
        '''AND NOT CHP_FLT_DI AND CHP_REM AND NOT P06_Isolatable;
ACH_Auto_OP := START_ACH_REQ AND NOT CH_MS AND NOT TST_MS
    AND NOT P06_SeqFault AND NOT P06_ConfigFault;''')
    add_section('CHP01', 'P06_FINAL_GUARD', 'Drive_OP',
        (BASE / 'sources/CHP01/P06_FINAL_GUARD.st').read_text())
    replace('CHP01', 'FPM_ENA', 'FPM_STANDBY := (NOT ACH_EN)',
        'FPM_STANDBY := ((P06_State = 0) OR (P06_State = 900)) AND (NOT ACH_EN)')
    replace('CHP01', 'FPM_ENA', 'IF FPM_ENA[6] AND (CHV02_FB',
        'IF FPM_ENA[6] AND (CHV01_FB > CHV_OSTP) AND (CHV02_FB')
    replace('CHP01', 'Chemical_Water_Treatment',
        'IF CHE_DUE AND (NOT Chemical_Mode_ENA[0])',
        'IF CHE_DUE AND P06_ChemGrant AND (P06_State = 0) AND (NOT Chemical_Mode_ENA[0])')
    change('CHP01', 'ALARM', section('CHP01', 'ALARM').text
        + '\nALM_UNIT_ANY := ALM_UNIT_ANY OR P06_SeqFault OR P06_StopFault OR P06_ConfigFault;\n')
    tx = '''
(* P06 extension: same 30-word status block, previously reserved +24/+25. *)
P06_TX_VER := 2606;
P06_TX_EXT := 0;
IF P06_SeqFault THEN P06_TX_EXT := P06_TX_EXT OR 16#0001; END_IF;
IF UNIT_ENABLE AND NOT P06_SeqFault AND NOT P06_ConfigFault AND NOT TST_MS
    AND NOT LOCAL_EN AND P06_TempValid AND (P06_State = 0) AND P06_TOff.Q
    AND NOT ACH_RUN AND NOT CHP_RUN THEN
    P06_TX_EXT := P06_TX_EXT OR 16#0002;
END_IF;
IF (P06_State = 40) AND P06_TOn.Q THEN P06_TX_EXT := P06_TX_EXT OR 16#0004; END_IF;
IF P06_TempValid THEN P06_TX_EXT := P06_TX_EXT OR 16#0008; END_IF;
IF P06_StopFault THEN P06_TX_EXT := P06_TX_EXT OR 16#0010; END_IF;
IF CHE_DUE THEN P06_TX_EXT := P06_TX_EXT OR 16#0020; END_IF;
IF LOCAL_EN THEN P06_TX_EXT := P06_TX_EXT OR 16#0040; END_IF;
(* Report the selected VALID temperature twice, never a failed held channel. *)
IF NOT (CHS_T01_UnderRange OR CHS_T01_OverRange) THEN P06_QualTemp := CHS_T01; END_IF;
IF NOT (CHS_T02_UnderRange OR CHS_T02_OverRange) THEN
    IF CHS_T01_UnderRange OR CHS_T01_OverRange THEN P06_QualTemp := CHS_T02;
    ELSE P06_QualTemp := MAX(P06_QualTemp, CHS_T02);
    END_IF;
END_IF;
TX_CHST01 := REAL_TO_INT(P06_QualTemp * 100.0);
TX_CHST02 := TX_CHST01;
TX2_BLK[9] := TX_CHST01; TX2_BLK[10] := TX_CHST02;
TX2_BLK[24] := P06_TX_VER; TX2_BLK[25] := P06_TX_EXT;
'''
    change('CHP01', 'IF_TX', section('CHP01', 'IF_TX').text + tx)

    boot = '''(* P06 per-peer recovery starts on every cold/warm restart. *)
P06_Boot := NOT P06_InitDone OR %S0 OR %S1;
P06_InitDone := TRUE;
IF P06_Boot THEN
    P06_StartID := 0; P06_StopID := 0; P06_RotOld := 0; P06_RotNew := 0;
    P06_SpaceActive := TRUE; P06_SpaceReset := TRUE;
    FOR I := 1 TO 5 DO P06_Known[I] := FALSE; END_FOR;
END_IF;
'''
    change('SMCL', 'S00_INIT', boot + section('SMCL', 'S00_INIT').text)
    old = section('SMCL', 'S20_CALC').text
    start = old.index('FLOW_A_OK :=')
    end = old.index('(* Redundant flow meter deviation *)')
    flow = '''(* P06 independent redundant selection per loop. *)
FLOW_A_OK := OK_CHWR_FL01 OR OK_CHWS_FL01;
FLOW_B_OK := OK_CHWR_FL02 OR OK_CHWS_FL02;
ALM_FLOW_A_FAIL := NOT FLOW_A_OK; ALM_FLOW_B_FAIL := NOT FLOW_B_OK;
IF (FL_SEL_A = 2) AND OK_CHWS_FL01 THEN FLOW_A := V_CHWS_FL01;
ELSIF OK_CHWR_FL01 THEN FLOW_A := V_CHWR_FL01;
ELSIF OK_CHWS_FL01 THEN FLOW_A := V_CHWS_FL01;
END_IF;
IF (FL_SEL_B = 2) AND OK_CHWS_FL02 THEN FLOW_B := V_CHWS_FL02;
ELSIF OK_CHWR_FL02 THEN FLOW_B := V_CHWR_FL02;
ELSIF OK_CHWS_FL02 THEN FLOW_B := V_CHWS_FL02;
END_IF;
FLOW_STATE := 0;
IF NOT FLOW_A_OK OR NOT FLOW_B_OK THEN FLOW_STATE := 9; END_IF;
P06_LoadValid := FLOW_A_OK AND FLOW_B_OK AND OK_CHWR_T01 AND OK_CHWS_T01
    AND OK_CHWR_T02 AND OK_CHWS_T02;

'''
    old = old[:start] + flow + old[end:]
    old = old.replace('TOT_CHF := MAX(V_CHWR_FL01 + V_CHWR_FL02, V_CHWS_FL01 + V_CHWS_FL02);',
        'TOT_CHF := FLOW_A + FLOW_B;')
    change('SMCL', 'S20_CALC', old)
    rx = ''
    for i in range(1, 6):
        rx += f'P06_Version[{i}] := P06_RX_VER_{i}; P06_Ext[{i}] := P06_RX_EXT_{i};\n'
    change('SMCL', 'S10_IF_RX', section('SMCL', 'S10_IF_RX').text + '\n' + rx)
    change('SMCL', 'S30_STAGE', (BASE / 'sources/SMCL/S30_STAGE.st').read_text())
    for i in range(1, 6):
        replace('SMCL', 'S40_IF_TX',
            f'IF NOT RCV_ACT THEN CH{i}_CMD_BITS := CH{i}_CMD_BITS OR 16#0020; END_IF;',
            f'IF NOT RCV_ACT AND P06_Known[{i}] AND P06_Fresh[{i}] AND NOT P06_Local[{i}] THEN CH{i}_CMD_BITS := CH{i}_CMD_BITS OR 16#0020; END_IF;')
    grants = '\n'
    for i in range(1, 6):
        grants += f'IF P06_ChemID = {i} THEN CH{i}_CMD_BITS := CH{i}_CMD_BITS OR 16#0040; END_IF;\n'
    change('SMCL', 'S40_IF_TX', section('SMCL', 'S40_IF_TX').text + grants)
    change('SMCL', 'S50_ALARM', section('SMCL', 'S50_ALARM').text + '''
GEN_ALM := GEN_ALM OR P06_ConfigFault OR P06_UnknownAlarm OR P06_StartAlarm
    OR P06_StopAlarm OR P06_RotateAlarm;
''')
    # Simulated peers must explicitly identify the NEW protocol; real mode unchanged.
    sim = '\nIF SIM_M340_EN THEN\n'
    for i in range(1, 6):
        sim += f'''    P06_RX_VER_{i} := 2606; P06_RX_EXT_{i} := 8;
    IF NOT SIM_ENA[{i}] AND NOT SIM_FAULT[{i}] AND NOT SIM_MS[{i}] AND NOT SIM_PWRLOSS[{i}] THEN
        P06_RX_EXT_{i} := P06_RX_EXT_{i} OR 16#0002;
    END_IF;
    IF SIM_RUN[{i}] THEN P06_RX_EXT_{i} := P06_RX_EXT_{i} OR 16#0004; END_IF;
    IF NOT SIM_RUN[{i}] AND NOT SIM_ENA[{i}] THEN
        CH{i}_STS_BITS1 := CH{i}_STS_BITS1 OR 16#0400;
    END_IF;
'''
    sim += 'END_IF;\n'
    change('SMCL', 'S90_SIM_M340', section('SMCL', 'S90_SIM_M340').text + sim)

    unit_types = dict(P06_State='INT', P06_FaultCode='INT', P06_TX_VER='INT',
                      P06_TX_EXT='INT', P06_QualTemp='REAL', P06_OffPreset='TIME')
    group_types = {n: 'INT' for n in ['P06_StartID','P06_StopID','P06_RotOld','P06_RotNew',
        'P06_RotTarget','P06_Occupied','P06_HealthyRequested','P06_RunningOut','P06_ChemID']}
    for n in ['P06_Known','P06_Fresh','P06_Ready','P06_CanStop','P06_TempOK','P06_Local','P06_Inhibit']:
        group_types[n] = 'ARRAY[1..5] OF BOOL'
    for n in ['P06_Version','P06_Ext']:
        group_types[n] = 'ARRAY[1..5] OF INT'
    group_located = {}
    for i in range(1, 6):
        for suffix, offset in [('VER',24),('EXT',25)]:
            name = f'P06_RX_{suffix}_{i}'
            group_types[name] = 'INT'
            group_located[name] = f'%MW{400 + (i-1)*30 + offset}'
    manifests = {
        'CHP01': variables('CHP01', unit_types, {'P06_TX_VER':'%MW724','P06_TX_EXT':'%MW725'}),
        'SMCL': variables('SMCL', group_types, group_located)}
    for key, r in ROOTS.items():
        r.find('contentHeader').set('version', '0.0.6')
        for p in r.findall('program'):
            node = p.find('STSource')
            if node is not None:
                name = p.find('identProgram').get('name')
                (BASE / 'sources' / key / (name + '.st')).write_text(node.text or '')
        out = BASE / ('CHP01-P06.ZEF' if key == 'CHP01' else 'SMCL-P06.ZEF')
        raw = ET.tostring(r, encoding='utf-8', xml_declaration=True)
        with zipfile.ZipFile(ORIGINALS[key]) as old, zipfile.ZipFile(out, 'w') as new:
            for member in old.infolist():
                payload = old.read(member.filename)
                if member.filename == 'unitpro.xef':
                    payload = raw
                elif member.filename == 'props.xml':
                    props = ET.fromstring(payload)
                    props.find('AppBuilt').text = 'FALSE'
                    payload = ET.tostring(props, encoding='utf-8', xml_declaration=True)
                new.writestr(member, payload)
        assert zipfile.ZipFile(out).testzip() is None
        (BASE / (key + '-source.xml')).write_bytes(raw)
    (BASE / 'variables.json').write_text(json.dumps(manifests, ensure_ascii=False, indent=2) + '\n')
    (BASE / 'checksums.json').write_text(json.dumps({
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in [*ORIGINALS.values(), BASE/'CHP01-P06.ZEF', BASE/'SMCL-P06.ZEF']}, indent=2) + '\n')


if __name__ == '__main__':
    build(*sys.argv[1:])

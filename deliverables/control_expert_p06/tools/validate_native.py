"""Structural/source validation, NOT a Schneider build or import check."""
from pathlib import Path
import sys, json, zipfile, re, xml.etree.ElementTree as ET
from blark.parse import parse_source_code

BASE=Path(__file__).resolve().parents[1]


def validate():
    report={}
    for key in ('CHP01','SMCL'):
        with zipfile.ZipFile(BASE/(key+'-P06.ZEF')) as z:
            assert z.testzip() is None
            r=ET.fromstring(z.read('unitpro.xef'))
            assert ET.fromstring(z.read('props.xml')).findtext('AppBuilt')=='FALSE'
        originals=ET.parse(BASE/(key+'-source.xml')).getroot()
        assert ET.tostring(r)==ET.tostring(originals)
        declarations={v.get('name') for v in r.findall('./dataBlock/variables')}
        functions={x.get('nameOfEFType') for x in r.findall('EFSource')}
        unknown=set(); parsed=[]
        for p in r.findall('program'):
            source=p.find('STSource')
            if source is None or 'P06_' not in (source.text or ''):continue
            name=p.find('identProgram').get('name')
            # blark does not lex Schneider %S system bits. Normalize ONLY the
            # parser input, never the native engineering source.
            parser_text=re.sub(r'%S(\d+)',r'PARSER_SYS_S\1',source.text)
            result=parse_source_code(parser_text,starting_rule='statement_list')
            if result.exception:raise result.exception
            parsed.append(name)
            def walk(node,parent=None,index=None):
                if not hasattr(node,'data'):return
                if node.data=='variable_name':
                    identifier=str(node.children[0])
                    # Formal argument names and structure field selectors aren't globals.
                    ignored=parent is not None and (parent.data=='field_selector'
                        or (parent.data in ('param_assignment','output_parameter_assignment')
                            and index in (0,1) and any(getattr(c,'data',None)=='expression' for c in parent.children)))
                    if not ignored and identifier not in declarations and identifier not in functions and not identifier.startswith('PARSER_SYS_'):
                        unknown.add(identifier)
                for i,child in enumerate(node.children):walk(child,node,i)
            walk(result.tree)
        assert not unknown,(key,sorted(unknown))
        report[key]=dict(parsed_sections=parsed,undeclared_identifiers=[],archive_crc='passed',
                         compiler_validation='NOT RUN',software='Control Expert V16.2',
                         parser_only_normalization='Schneider %S system bits mapped to symbolic names; native source untouched')
    # Check exact preservation against supplied input archives when paths provided.
    if len(sys.argv)==3:
        for key,path in zip(('CHP01','SMCL'),sys.argv[1:]):
            with zipfile.ZipFile(path) as a,zipfile.ZipFile(BASE/(key+'-P06.ZEF')) as b:
                assert a.namelist()==b.namelist()
                for name in a.namelist():
                    if name not in ('unitpro.xef','props.xml'):assert a.read(name)==b.read(name)
                old=ET.fromstring(a.read('unitpro.xef'));new=ET.fromstring(b.read('unitpro.xef'))
                for tag in ('IOConf','commParameters'):
                    assert ET.tostring(old.find(tag))==ET.tostring(new.find(tag))
                oldvars={v.get('name'):dict(v.attrib) for v in old.findall('./dataBlock/variables')}
                newvars={v.get('name'):dict(v.attrib) for v in new.findall('./dataBlock/variables')}
                assert all(newvars[n]==attrs for n,attrs in oldvars.items())
                report[key]['hardware_config_and_existing_variable_addresses']='unchanged'
                report[key]['unchanged_non_source_archive_members']='byte-identical'
    (BASE/'validation-structure.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__=='__main__':validate()

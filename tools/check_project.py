"""Check generated resources, language references, links and maintenance inventory."""
import argparse
import hashlib
import json
import re
import os
from pathlib import Path
from urllib.parse import unquote
from resource_keys import ROOT
from check_design import DESIGN_PATH, inspect_design

def project_files():
    excluded = {'build', '.dart_tool', '.git', '.gradle', '.local', 'qa', 'signing', '__pycache__', 'node_modules'}
    for directory, children, names in os.walk(ROOT):
        base = Path(directory)
        children[:] = [name for name in children if name not in excluded and
                       (base/name).relative_to(ROOT) != DESIGN_PATH]
        for name in names:
            if name not in ('key.properties', '.DS_Store'):
                yield base/name

project_paths = list(project_files())
design = inspect_design()
errors=list(design['errors'])
def require(ok,message):
    if not ok: errors.append(message)
def read(relative): return json.loads((ROOT/relative).read_text())
assets=ROOT/'app/assets'
lang=read('app/assets/i18n/zh_CN.json')
catalog=read('app/assets/catalog.json')
native=read('app/android/app/src/main/assets/catalog.json')
entities=read('app/assets/entities.json')
icons=read('app/assets/icon-manifest.json')['icons']
require(len(catalog)==92,'catalog count')
require(len({e['id'] for e in catalog})==len(catalog),'duplicate metric IDs')
require(len(entities)==173 and len({e['id'] for e in entities})==173,'control IDs')
require(len(icons)==90 and len({e['id'] for e in icons})==90,'icon IDs')
require(native[:len(catalog)]==catalog,'native metric mirror')
require((ROOT/'app/android/app/src/main/assets/entities.json').read_bytes()==(assets/'entities.json').read_bytes(),'native entity mirror')
require((ROOT/'app/android/app/src/main/assets/i18n/zh_CN.json').read_bytes()==(assets/'i18n/zh_CN.json').read_bytes(),'native language mirror')
icon_ids={e['id'] for e in icons}
for e in catalog+entities+icons:
    for key in ['nameKey','categoryKey']:
        require(e.get(key) in lang,f'{e.get("id")}: missing {key}')
    if 'icon' in e and e['icon']:require(e['icon'] in icon_ids,f'{e["id"]}: missing icon')
for e in entities:
    require(all(o.get('labelKey') in lang for o in e['options']),e['id']+': option language')
    if e['validation']=='inferred':require(e['readField'] is None and not e['feedbackFields'],e['id']+': inferred demand')
for i in icons:
    p=assets/'icons'/Path(i['asset']).name
    require(p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==i['sha256'],i['id']+': icon hash')
for base,pattern in [('app/lib',r"Strings\.text\(['\"]([^'\"]+)"),('app/android/app/src/main/kotlin',r'NativeStrings\.(\w+)')]:
    for p in (ROOT/base).rglob('*'):
        if p.suffix not in ('.dart','.kt') or p.name in ['defaults.g.dart','NativeStrings.kt']:continue
        for key in re.findall(pattern,p.read_text()):
            if key not in ['text']:
                if '$' in key:
                    pieces=re.split(r'(\$\{[^}]+\}|\$[a-zA-Z_]\w*)',key)
                    template=''.join('[a-zA-Z0-9_]+' if v.startswith('$') else re.escape(v) for v in pieces)
                    require(any(re.fullmatch(template,k) for k in lang),str(p.relative_to(ROOT))+': missing language template '+key)
                else:require(key in lang,str(p.relative_to(ROOT))+': missing language '+key)
for key in ['ha_type','ha_area','ha_device']+['ha_status_'+state for state in ('connected','loading','disabled','disconnected','auth_failed','permission','error')]:
    require(key in lang,'missing HA directory language '+key)
links=0
for p in (p for p in project_paths if p.suffix == '.md'):
    relative=p.relative_to(ROOT)
    if any(a in relative.parts for a in ('build','.dart_tool','.git','.gradle')):continue
    for target in re.findall(r'\]\(([^)]+)\)',p.read_text()):
        target=target.strip('<>')
        if target.startswith(('http:','https:','app:','codex:','mailto:')):continue
        file=unquote(target.split('#')[0])
        if not file:continue
        path=Path(file) if file.startswith('/') else p.parent/file
        links+=1
        require(path.exists(),str(relative)+': broken link '+target)
files=[]
for p in project_paths:
    relative=p.relative_to(ROOT)
    if not p.is_file() or any(a in relative.parts for a in ('build','.dart_tool','.git','.gradle','signing')) or p.name=='key.properties':continue
    files.append({'path':str(relative),'bytes':p.stat().st_size,'kind':'evidence/review' if relative.parts[0] in ('checkpoints','design-previews') or 'qa' in relative.parts else 'historical documentation' if 'archive' in relative.parts else 'generated resource' if p.name in ('NativeStrings.kt','defaults.g.dart','VerifiedControlPlans.kt','InferredControlPlans.kt') else 'project source/resource'})
result={'errors':errors,'designDependency':design,'counts':{'metrics':len(catalog),'entities':len(entities),'icons':len(icons),'languageKeys':len(lang),'localLinks':links,'inventoriedFiles':len(files)},'scope':'APP project; build caches, credentials and external submodule contents excluded'}
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',default='app/qa/project-check',help='Report directory relative to the APP project root')
qa=ROOT/parser.parse_args().output;qa.mkdir(parents=True,exist_ok=True)
(qa/'project-check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
(qa/'file-inventory.json').write_text(json.dumps(files,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False,indent=2))
raise SystemExit(bool(errors))

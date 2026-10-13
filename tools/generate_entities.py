"""Generate UI/HA metadata from the existing native whitelist, never extend it."""
import json
import re
import shutil
from pathlib import Path
from resource_keys import ROOT, LanguageKeys

app = ROOT / 'app'
native = app / 'android/app/src/main/kotlin/app/skyinfo/vehicle'
keys = LanguageKeys()
manifest = json.loads((ROOT/'design-assets/icons/manifest.json').read_text())
icons = {e['action_id']: e['icon_id'] for e in manifest['controls']}

def legacy_label(action, value):
    if action == 'ac_temperature': return f'{value}°C'
    if action == 'ac_wind_level': return f'{value}档'
    if action == 'ac_cycle': return ['外循环', '内循环'][value]
    if action == 'ac_control_mode': return ['自动', '手动'][value]
    if action == 'wireless_charging': return '开启' if value == 1 else '关闭'
    if action == 'steering_wheel_heat': return '关闭' if value == 1 else '开启'
    if action.startswith('seat_'): return '关闭' if value == 1 else f'{value-1}档'
    return '关闭' if value == 0 else '开启'

entries = []
pattern = r'Definition\("([^\"]+)",NativeStrings\.(\w+),(\d+),(-?\d+),(-?\d+),(\d+),(\d+)(?:,true)?\)'
for action, name_key, device, read, write, lo, hi in re.findall(pattern, (native/'VehicleControls.kt').read_text()):
    options = [dict(value=v, label=legacy_label(action,v), expected=v) for v in range(int(lo),int(hi)+1)]
    read_field = f'{device}/5/{read}'
    category = '座椅' if action.startswith('seat_') or action == 'steering_wheel_heat' else '充电及其他设备' if action == 'wireless_charging' else '空调'
    entries.append(dict(id=action,name=keys.values[name_key],category=category,validation='verified',readField=read_field,
                        options=options,states={str(o['expected']):o['label'] for o in options},
                        feedbackFields=[read_field]+(['1000/5/1077936176'] if action=='ac_temperature' else [])))
assert len(entries) == 13
for name in ('controls.json', 'inferred-controls.json'):
    for row in json.loads((app/'assets'/name).read_text()):
        inferred = row.get('validation') == 'inferred'
        read = row['read']
        feedback = [] if inferred else [f"{read['device']}/5/{f}" for f in read['features']]
        entries.append(dict(id=row['id'], name=row['name'], category=row['category'], validation='inferred' if inferred else 'verified',
                            readField=feedback[0] if feedback else None,feedbackFields=feedback,
                            options=[{k:o.get(k) for k in ('value','label','expected')} for o in row['options']],
                            states={str(o['expected']):o['label'] for o in row['options'] if o.get('expected') is not None}))
for entry in entries:
    entry['icon'] = icons.get(entry['id'],'tabler-car')
    entry['unit'] = '°C' if entry['id'] in ('ac_temperature','main_temp','deputy_temp') else '档' if entry['id']=='ac_wind_level' else ''
    options = entry['options']
    toggle = len(options)==2 and {o['label'] for o in options}=={'开启','关闭'} and entry['readField'] and all(o['expected'] is not None for o in options)
    entry['capability'] = 'number' if entry['id'] in ('ac_temperature','ac_wind_level') else 'toggle' if toggle else 'select' if entry['readField'] and entry['states'] and len(options)>1 else 'button'
    keys.label(entry)
    for option in options: option['labelKey'] = keys.key(option['label'])
    entry['stateKeys'] = {raw:keys.key(label) for raw,label in entry['states'].items()}
assert len(entries)==173 and len({e['id'] for e in entries})==173
output = json.dumps(entries,ensure_ascii=False,indent=2)+'\n'
(app/'assets/entities.json').write_text(output)
(app/'android/app/src/main/assets/entities.json').write_text(output)
for icon in manifest['icons']:
    keys.label(icon)
    shutil.copyfile(ROOT/'design-assets/icons'/icon['asset'],app/'assets/icons'/Path(icon['asset']).name)
(app/'assets/icon-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
keys.save()
print(f'{len(entries)} entities, {len(manifest["icons"])} icons generated')

import json
import re
from pathlib import Path
from resource_keys import LanguageKeys

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'design-assets/icons/manifest.json').read_text())
units = {}
for line in (root / 'docs/MQTT数据分类.md').read_text().splitlines():
    match = re.match(r'\| (.+?) \| `([^`]+)` \| (.+?) \|$', line)
    if match:
        units[match[2]] = match[3]
adaptation_path = root / "docs/车辆适配结果.json"
adaptation = json.loads(adaptation_path.read_text()) if adaptation_path.exists() else {}
support = {f["id"]: f for f in adaptation.get("fields", [])}
temperature_ids = {'1014/5/1148190752', '1014/5/1148190736', '1014/5/1148190776'}
annotated_units = {'1014/5/1147142192': 'mV', '1014/5/1147142160': 'mV', '1006/5/1186988096': 'rpm', '1039/5/1302331672': '°C', '1039/5/1178624024': '°C', '1039/5/1302331756': '°C', '1039/5/1178624040': '°C', '1039/5/1302331648': '°C', '1039/5/1178624016': '°C', '1039/5/1302331748': '°C', '1039/5/1178624032': '°C', '1000/5/1320181776': '°C', '1039/5/919601208': '°C', '1007/5/1246797848': '°C', '1007/5/1246797860': '°C', '1007/5/1246797872': '°C', '1007/5/1246797884': '°C'}
annotated_units.update({'1012/5/1141899272': 'rpm', '1012/5/621805576': 'rpm', '1009/7/1186988040': 'A', '1009/7/1186988056': 'A'})
state_labels = {key: {'0':'关闭','1':'打开'} for key in ['1001/5/692060168','1001/5/692060170','1001/5/692060172','1001/5/692060174','1001/5/692060188','1001/5/692060186']}
state_labels.update({
    '1000/5/1077936144': {'0':'关闭','1':'开启'},
    '1000/5/1077936137': {'0':'关闭','1':'开启'},
    '1011/5/555745336': {'1':'P','2':'R','3':'N','4':'D'},
    '1032/5/1081081864': {'0':'无效','1':'解锁','2':'上锁'},
    '1009/5/876609586': {'1':'未连接','2':'交流','3':'直流','4':'交流及直流','5':'对外放电'},
    '1009/5/876609560': {'0':'准备','1':'充电','2':'完成','3':'放电','4':'终止','13':'暂停'},
    '1009/5/89128973': {'0':'未连接','1':'已连接'},
    '1009/5/1132462112': {'0':'无效','1':'开启','2':'关闭'},
    '1006/5/888143882': {'0':'无效','1':'发电','2':'结束','3':'错误'},
})
fields = []
for f in manifest['fields']:
    source = f['field_id']
    if source.startswith('derived.'):
        continue
    unit = units.get(source, '')
    hidden = not (f['name'].startswith('SOC') or '挡位' in f['name'] or '踏板深度' in f['name'] or '窗开度' in f['name'])
    fields.append(dict(id=source, name=f['name'], category=f['category'], icon=f['icon_id'],
        unit=unit if unit not in ['原值', '配对单位', '枚举'] else '',
        encoding=unit or '文本', displayAllowed=hidden,
        entityKey='low_voltage' if source == '1032/7/1128267816' else
        'android_version' if source == 'system.android_version' else
        'firmware_version' if source == 'system.firmware_version' else
        'gnss_altitude' if source == 'location.gnss_altitude' else
        source.replace('/', '_').replace('-', 'n'), subscription=support.get(source, {}).get('subscription', 'unverified'),
        verifiedFirmware=adaptation.get('firmware', ''), shellRead=support.get(source, {}).get('shell_quality', 'unverified')))
    if source == 'location.gnss_altitude':
        fields[-1].update(valueType='number', unitConfidence='documented', altitudeReference='WGS84', subscription='passive_location')
    if source in {'1014/7/1246777400','1014/5/1145045040','1012/5/339738642',
        '1013/5/874512392','1013/5/874512400','1032/7/1128267816',
        '1001/5/947912728','1001/5/1267728400','1001/5/947912736','1001/5/947912752'}:
        fields[-1].update(unitConfidence='documented')
    confirmed_names = {'1005/5/1031798840':'压缩机功耗候选',
        '1005/5/1320169504':'PTC功耗候选','1012/5/339738656':'ENGINE_POWER候选',
        '1000/5/1031798832':'车内温度候选','1014/5/1145045032':'电池健康度候选'}
    if source in confirmed_names:
        fields[-1].update(definitionVersion=2, unitConfidence='user_supplied',
            legacyNames=[confirmed_names[source]] + (['ENGINE_POWER'] if source == '1012/5/339738656' else []))
    if source == '1012/5/339738656':
        fields[-1].update(definitionVersion=3, legacyUnits=['W'])
    if source == '1038/5/303038502':
        fields[-1].update(definitionVersion=2, displayConfidence='user_supplied',
            legacyNames=['AEB激活候选'], rawDisplay=True)
    if source in {'1009/5/1145045000', '1009/7/1145045016'}:
        fields[-1].update(definitionVersion=2, unitConfidence='user_supplied')
    if source in annotated_units:
        assert unit == annotated_units[source]
        fields[-1].update(definitionVersion=2, unitConfidence='user_supplied')
    if source == '1012/5/1141899272':
        fields[-1].update(valueScale=-1)
    if source == '1039/5/677380120':
        fields[-1].update(unit='A', encoding='A', valueScale=0.1, valueOffset=-3000,
            definitionVersion=2, unitConfidence='user_supplied')
    if source in temperature_ids:
        fields[-1].update(unit='°C', encoding='°C', valueOffset=-30,
            definitionVersion=2, unitConfidence='user_supplied')
    if source in {'1000/5/1077936168', '1000/5/1077936176', '1000/5/1077936184'}:
        fields[-1].update(unit='°C', encoding='°C', unitField='1000/5/1077936167', definitionVersion=2)
    if source == '1014/7/1246760996':
        fields[-1].update(unitField='1007/5/1246761027', definitionVersion=2)
    if source in state_labels:
        fields[-1].update(stateLabels=state_labels[source], definitionVersion=2)
fields.insert(8, dict(id='derived.battery_power', name='动力电池功率', category='动力电池',
    icon='tabler-battery-spark', unit='kW', encoding='kW', displayAllowed=True,
    entityKey='battery_power', subscription='derived', definitionVersion=2,
    unitConfidence='user_supplied', derivedInputs=['1009/5/1145045000', '1039/5/677380120'],
    formula='voltage * current / 1000'))
internal = dict(id='1000/5/1077936167', name='空调温度单位', category='内部依赖', icon='', unit='',
    encoding='枚举', displayAllowed=False, entityKey='internal_ac_temperature_unit', subscription='unverified')
language = LanguageKeys()
for field in fields + [internal]:
    language.label(field)
    if "stateLabels" in field:
        field["stateLabelKeys"] = {raw:language.key(label) for raw,label in field["stateLabels"].items()}
language.save()
for path, contents in [(root / 'app/assets/catalog.json', fields), (root / 'app/android/app/src/main/assets/catalog.json', fields + [internal])]:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(contents, ensure_ascii=False, indent=2) + '\n')
print(f'{len(fields)} fields, {len(manifest["icons"])} icons')

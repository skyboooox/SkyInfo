"""Mirror reviewed public control plans into Kotlin without expanding operations."""
import json
from resource_keys import ROOT

native = ROOT / 'app/android/app/src/main/kotlin/app/skyinfo/vehicle'
for filename, variable, output, count in (
    ('controls.json', 'verifiedControlPlans', 'VerifiedControlPlans.kt', 26),
    ('inferred-controls.json', 'inferredControlPlans', 'InferredControlPlans.kt', 134),
):
    entries = json.loads((ROOT / 'app/assets' / filename).read_text())
    assert len(entries) == count and len({row['id'] for row in entries}) == count
    for row in entries:
        assert row['protocol'] == 'CANFD' and row['options']
        for option in row['options']:
            assert type(option['value']) is int
            for plan in [option['write'], option.get('stop')]:
                if plan is None:
                    continue
                assert plan['command'] in ('SET_INT', 'SET_INT_ARRAY')
                assert type(plan['device']) is int and 1 <= plan['device'] <= 2000
                assert len(plan['features']) == len(plan['values']) > 0
                assert all(type(value) is int and -(2**31) <= value < 2**31
                           for value in plan['features'] + plan['values'])
                assert all(plan['features'])
    compact = json.dumps(entries, ensure_ascii=False, separators=(',', ':'))
    assert '$' not in compact and '"""' not in compact
    if variable == 'verifiedControlPlans':
        body = f'internal const val {variable} = """{compact}"""\n'
    else:
        chunks = [compact[index:index + 8000] for index in range(0, len(compact), 8000)]
        body = f'internal val {variable} = listOf(\n' + ',\n'.join(
            f'    """{chunk}"""' for chunk in chunks
        ) + '\n).joinToString("")\n'
    (native / output).write_text('package app.skyinfo.vehicle\n\n' + body)
    print(f'{filename}: {count} reviewed plans mirrored')

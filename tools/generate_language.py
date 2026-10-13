"""Generate Flutter and Android fallback resources from the shared language file."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'app/assets/i18n/zh_CN.json'


def generate():
    resources = json.loads(SOURCE.read_text())
    def dart_string(text):
        return json.dumps(text, ensure_ascii=False).replace('$', r'\$')
    dart = 'const defaultStrings = <String, String>{\n' + ''.join(
        f'  {json.dumps(key)}: {dart_string(value)},\n' for key, value in resources.items()) + '};\n'
    (ROOT / 'app/lib/l10n/defaults.g.dart').write_text(dart)
    kotlin = 'package app.skyinfo.vehicle\n\nobject NativeStrings {\n' + ''.join(
        f'    const val {key} = {dart_string(value)}\n' for key, value in resources.items())
    kotlin += '''    fun text(key: String, values: Map<String, Any?> = emptyMap()): String {
        val template = defaults[key] ?: key
        return Regex("\\\\{([a-zA-Z0-9_]+)\\\\}").replace(template) { match -> values[match.groupValues[1]]?.toString() ?: match.value }
    }
    private val defaults by lazy { mapOf(
'''
    kotlin += ',\n'.join(f'        "{key}" to {key}' for key in resources) + '\n    ) }\n}\n'
    (ROOT / 'app/android/app/src/main/kotlin/app/skyinfo/vehicle/NativeStrings.kt').write_text(kotlin)
    destination = ROOT / 'app/android/app/src/main/assets/i18n/zh_CN.json'
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(SOURCE.read_text())
    print(f'{len(resources)} language entries generated')


if __name__ == '__main__':
    generate()

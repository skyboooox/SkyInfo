"""Check the staged/committed public file set without printing sensitive values."""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).decode().split('\0')
issues = []
for name in filter(None, paths):
    path = ROOT / name
    if path.is_dir():
        continue  # Submodule has its own history and policy.
    forbidden = {'qa', 'checkpoints', 'design-previews', 'signing', 'build', '.local', '.dart_tool'}
    if forbidden.intersection(path.relative_to(ROOT).parts) or path.name in {'key.properties', 'local.properties', '.DS_Store'}:
        issues.append({'path': name, 'reason': 'private/generated file'})
    if path.suffix.lower() in {'.jks', '.keystore', '.p12', '.pfx', '.pem', '.key', '.apk', '.aab', '.fig'}:
        issues.append({'path': name, 'reason': 'credential or binary release'})
    if path.suffix.lower() in {'.jar', '.aar', '.so'} and name != 'app/android/gradle/wrapper/gradle-wrapper.jar':
        issues.append({'path': name, 'reason': 'unexpected vendor binary'})
    if path.stat().st_size > 10_000_000:
        issues.append({'path': name, 'reason': 'unexpected large file'})
    try:
        content = path.read_text()
    except UnicodeDecodeError:
        continue
    patterns = {
        'private key': r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        'GitHub credential': r'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}',
        'JWT credential': r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}',
        'personal absolute path': r'/(?:Users|home)/[A-Za-z0-9_.-]+/',
    }
    for reason, pattern in patterns.items():
        if re.search(pattern, content):
            issues.append({'path': name, 'reason': reason})
result = {'checkedFiles': len(list(filter(None, paths))), 'issues': issues,
          'scope': 'Tracked host files; run Gitleaks and review nested dependency separately before first publication'}
print(json.dumps(result, ensure_ascii=False, indent=2))
sys.exit(bool(issues))

"""Validate the pinned design dependency and Flutter theme aliases."""
import argparse
import json
import re
import subprocess
from pathlib import Path

from resource_keys import ROOT

DESIGN_PATH = Path('docs/design/fluorite-design')
DESIGN_URL = 'https://github.com/skyboooox/fluorite-design.git'
ALIASES = {
    'primary': 'acid', 'danger': 'red', 'accentBlue': 'blue',
    'positive': 'green', 'accentRose': 'rose',
}


def palette_errors(design, source):
    tokens = {}
    for name, light, dark in re.findall(
        r'^\|\s*(\w+)\s*\|\s*(#[0-9A-Fa-f]{6})\s*\|\s*(#[0-9A-Fa-f]{6})\s*\|',
        design, re.M,
    ):
        tokens[name] = (light.lower(), dark.lower())
    errors = []
    expected = {
        'paper', 'surface', 'field', 'ink', 'muted', 'grid', 'edge',
        'primary', 'onPrimary', 'accentBlue', 'positive', 'accentRose',
        'warning', 'danger',
    }
    if set(tokens) != expected:
        errors.append('Fluorite token schema changed; review the host mapping')
    for index, theme in enumerate(('light', 'dark')):
        block = re.search(r'static const '+theme+r' = Palette\((.*?)\n  \);', source, re.S)
        if not block:
            errors.append('missing Palette.'+theme)
            continue
        values = dict(re.findall(r'(\w+): Color\(0xff([0-9a-fA-F]{6})\)', block[1]))
        for token, pair in tokens.items():
            field = ALIASES.get(token, token)
            value = values.get(field)
            if token in ('primary', 'onPrimary'):
                pattern = (r'this\.acid = const Color\(0xff([0-9a-fA-F]{6})\)' if token == 'primary'
                           else r'onPrimary: const Color\(0xff([0-9a-fA-F]{6})\)')
                match = re.search(pattern, source)
                value = match[1] if match else None
            if value is None or '#'+value.lower() != pair[index]:
                errors.append(f'Palette.{theme}.{field} differs from Fluorite {token} {pair[index]}')
    return errors


def inspect_design(root=ROOT):
    dependency = root / DESIGN_PATH
    errors = []
    result = {'path': str(DESIGN_PATH), 'url': DESIGN_URL, 'errors': errors}
    for name in ('AGENTS.md', 'DESIGN.md', 'REVIEW.md', 'COMPONENTS.md'):
        if not (dependency/name).is_file():
            errors.append('missing Fluorite '+name+'; initialize the submodule')
    if errors:
        return result

    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()

    try:
        workspace = Path(git('rev-parse', '--show-toplevel'))
        relative = dependency.relative_to(workspace).as_posix()
        staged = git('-C', str(workspace), 'ls-files', '--stage', '--', relative).split()
        if len(staged) < 4 or staged[0] != '160000':
            errors.append('Fluorite must be a Git submodule, not a copied directory')
        else:
            result['pinnedCommit'] = staged[1]
        result['checkoutCommit'] = git('-C', str(dependency), 'rev-parse', 'HEAD')
        if result.get('pinnedCommit') != result['checkoutCommit']:
            errors.append('Fluorite checkout differs from the staged gitlink; review the upgrade')
        if git('-C', str(dependency), 'status', '--porcelain'):
            errors.append('Fluorite has local edits; maintain upstream changes in its own project')
        paths = git('config', '--file', str(workspace/'.gitmodules'), '--get-regexp', r'^submodule\..*\.path$')
        key = next((line.split()[0][:-4]+'url' for line in paths.splitlines()
                    if line.split(maxsplit=1)[1] == relative), None)
        if key is None or git('config', '--file', str(workspace/'.gitmodules'), '--get', key) != DESIGN_URL:
            errors.append('Fluorite submodule URL/path mismatch')
    except (subprocess.CalledProcessError, ValueError, IndexError) as error:
        errors.append('cannot verify Fluorite gitlink: '+str(error))
    errors.extend(palette_errors((dependency/'DESIGN.md').read_text(),
                                 (root/'app/lib/ui/industrial.dart').read_text()))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='Optional JSON report path')
    args = parser.parse_args()
    result = inspect_design()
    report = json.dumps(result, ensure_ascii=False, indent=2)+'\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report)
    print(report, end='')
    raise SystemExit(bool(result['errors']))

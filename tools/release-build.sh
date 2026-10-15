#!/bin/sh
set -eu
channel=${1:-alpha}
case "$channel" in
  alpha|beta|stable) ;;
  *) echo 'Usage: tools/release-build.sh [alpha|beta|stable]' >&2; exit 2 ;;
esac
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
./tools/docker.sh flutter clean
./tools/docker.sh flutter build apk --flavor "$channel" --release --target-platform android-arm64
python3 - "$channel" <<'PY'
import sys, zipfile, shutil
from pathlib import Path
apk = Path('app/build/app/outputs/flutter-apk') / f'app-{sys.argv[1]}-release.apk'
with zipfile.ZipFile(apk) as archive:
    names = set(archive.namelist())
    assert {n.split('/')[1] for n in names if n.startswith('lib/')} == {'arm64-v8a'}
    assert {'lib/arm64-v8a/libapp.so', 'lib/arm64-v8a/libflutter.so'} <= names
destination = Path('.local/builds') / apk.name
destination.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(apk, destination)
print(destination)
PY

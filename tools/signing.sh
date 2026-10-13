#!/bin/sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../app" && pwd)
if [ -f "$PROJECT_DIR/android/key.properties" ]; then
    exit 0
fi
mkdir -p "$PROJECT_DIR/android/signing"
chmod 700 "$PROJECT_DIR/android/signing"
umask 077
python3 - "$PROJECT_DIR/android/signing/password" <<'PY'
import secrets,sys
from pathlib import Path
Path(sys.argv[1]).write_text(secrets.token_urlsafe(48))
PY
"$(dirname -- "$0")/docker.sh" keytool -genkeypair -keystore /workspace/android/signing/release.jks \
    -storepass:file /workspace/android/signing/password -keypass:file /workspace/android/signing/password \
    -alias skyinfo -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=SkyInfo, O=SkyInfo' > /dev/null 2>&1
python3 - "$PROJECT_DIR" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); password=(root/'android/signing/password').read_text()
(root/'android/key.properties').write_text('storeFile=../signing/release.jks\nstorePassword='+password+'\nkeyPassword='+password+'\nkeyAlias=skyinfo\n')
(root/'android/signing/password').unlink()
PY
chmod 600 "$PROJECT_DIR/android/key.properties" "$PROJECT_DIR/android/signing/release.jks"

#!/bin/sh
set -eu
TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CERT_DIR="$TOOLS_DIR/../app/.local/mqtt-test"
BROKER_NAME="skyinfo-mqtt-test-$$"
SKYINFO_TEST_NETWORK="$BROKER_NAME"
export SKYINFO_TEST_NETWORK
if [ -d "$CERT_DIR" ]; then
  echo 'TLS测试目录已存在，请先关闭对应测试并移除目录。' >&2
  exit 1
fi
mkdir -p "$CERT_DIR"
cleanup() {
  docker rm -f "$BROKER_NAME" >/dev/null 2>&1 || true
  docker network rm "$SKYINFO_TEST_NETWORK" >/dev/null 2>&1 || true
  rm -rf "$CERT_DIR"
}
trap cleanup EXIT HUP INT TERM
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" -subj '/CN=SkyInfo Test CA' >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$CERT_DIR/server.key" -out "$CERT_DIR/server.csr" -subj '/CN=host.docker.internal' >/dev/null 2>&1
printf '%s\n' 'subjectAltName=DNS:host.docker.internal' > "$CERT_DIR/extensions"
openssl x509 -req -in "$CERT_DIR/server.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" -CAcreateserial -out "$CERT_DIR/server.crt" -days 2 -extfile "$CERT_DIR/extensions" >/dev/null 2>&1
chmod 644 "$CERT_DIR/server.key"
cat > "$CERT_DIR/mosquitto.conf" <<'CONF'
listener 18884
allow_anonymous true
cafile /mosquitto/config/ca.crt
certfile /mosquitto/config/server.crt
keyfile /mosquitto/config/server.key
persistence false
listener 18885
allow_anonymous true
CONF
docker network create "$SKYINFO_TEST_NETWORK" >/dev/null
docker run -d --name "$BROKER_NAME" --network "$SKYINFO_TEST_NETWORK" --network-alias host.docker.internal -v "$CERT_DIR:/mosquitto/config:ro" eclipse-mosquitto:2.0.22@sha256:199ea8ef2e35ec2b1b37e59cfd1dbae538ed4dfa4a2251a121a52215a6248a21 >/dev/null
"$TOOLS_DIR/docker.sh" sh -c 'cd android && SKYINFO_MQTT_TEST_TLS=1 SKYINFO_MQTT_TEST_TCP=1 ./gradlew :app:testAlphaDebugUnitTest :app:testBetaDebugUnitTest :app:testStableDebugUnitTest --rerun --no-daemon "$@"' sh "$@"

#!/bin/sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../app" && pwd)
IMAGE='skyinfo-build:3.44.0-ndk28.2'
docker build --quiet --platform linux/amd64 -t "$IMAGE" -f "$PROJECT_DIR/../tools/Dockerfile" "$PROJECT_DIR/../tools" >/dev/null
if [ -n "${SKYINFO_TEST_NETWORK:-}" ]; then
  set -- --network "$SKYINFO_TEST_NETWORK" "$IMAGE" "$@"
else
  set -- "$IMAGE" "$@"
fi
exec docker run --rm --platform linux/amd64 \
  -v "$PROJECT_DIR:/workspace" \
  -v skyinfo-pub-cache:/root/.pub-cache \
  -v skyinfo-gradle-cache:/root/.gradle \
  -v skyinfo-robolectric-cache:/root/.m2 \
  -w /workspace "$@"

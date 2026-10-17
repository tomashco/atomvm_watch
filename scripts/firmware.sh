#!/usr/bin/env bash
# Local firmware build in the ESP-IDF container (needs Docker). CI runs firmware/build.sh directly.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./versions.env; set +a
: "${IDF_IMAGE:?IDF_IMAGE not set (enter devenv shell)}"
docker run --rm -v "$PWD:/repo" -w /repo \
  -e FW_VERSION="${FW_VERSION:-dev}" -e ATOMVM_VERSION -e ATOMVM_M5_COMMIT "$IDF_IMAGE" bash -lc '
  set -e
  git config --global --add safe.directory "*"
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git cmake gperf zlib1g-dev erlang elixir rebar3 >/dev/null
  WORK=/repo/firmware/.work firmware/build.sh m5stickc_plus2 "$ATOMVM_VERSION" "$ATOMVM_M5_COMMIT" firmware/out'

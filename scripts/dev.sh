#!/usr/bin/env bash
# Dev loop: build the emulator pieces, then serve examples/clock in the emulator, rebuilding on change.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-m5-emu.sh
scripts/build-atomvmlib.sh
scripts/build-web.sh
cd examples/clock
mix deps.get
exec mix m5.emulate "$@"

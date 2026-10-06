#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
(cd m5_emu && rebar3 eunit)
(cd web && pnpm test)
scripts/build-m5-emu.sh
(cd m5_emu/test/smoke_app && rebar3 atomvm packbeam)
node m5_emu/test/node/smoke.mjs

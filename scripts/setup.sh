#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/fetch-atomvm.sh
scripts/build-atomvmlib.sh
(cd web && pnpm install)
if [ -d m5_emu ]; then
  (cd m5_emu && rebar3 get-deps)
fi
if [ -d examples/clock ] || [ -d m5_emu_mix ]; then
  mix local.hex --force
  mix local.rebar --force
fi
if [ -d examples/clock ]; then
  (cd examples/clock && mix deps.get)
fi
if [ -d m5_emu_mix ]; then
  (cd m5_emu_mix && mix deps.get)
fi
echo "setup complete"

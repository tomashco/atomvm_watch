#!/usr/bin/env bash
# Builds examples/clock into clock.avm and refreshes the committed e2e fixture
# web/e2e/fixtures/clock.avm. Also refreshes the smoke_app fixture used by the e2e replace step.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/web/e2e/fixtures"

cd "$root/examples/clock"
mix deps.get >/dev/null
mix atomvm.packbeam
cp clock.avm "$root/web/e2e/fixtures/clock.avm"
echo "fixture updated: web/e2e/fixtures/clock.avm"

cd "$root/m5_emu/test/smoke_app"
rebar3 atomvm packbeam >/dev/null
cp _build/default/lib/smoke_app.avm "$root/web/e2e/fixtures/smoke_app.avm"
echo "fixture updated: web/e2e/fixtures/smoke_app.avm"

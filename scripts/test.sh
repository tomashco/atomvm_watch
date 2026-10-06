#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
(cd m5_emu && rebar3 eunit)
(cd web && pnpm test)

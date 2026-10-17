#!/usr/bin/env bash
# Builds _build/stub_pack.avm: stub m5 and gpio modules, loaded after m5_emu.avm by the smoke test
# to prove the first pack wins on AtomVM. Uses the packbeam plugin fetched for m5_emu.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p _build/ebin
erlc -o _build/ebin src/*.erl
erl -noshell -pa ../../_build/default/plugins/*/ebin -eval '
  ok = packbeam_api:create("_build/stub_pack.avm", filelib:wildcard("_build/ebin/*.beam"),
                           #{prune => false, start_module => undefined}),
  halt().'
echo "wrote m5_emu/test/stub_pack/_build/stub_pack.avm"

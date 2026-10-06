#!/usr/bin/env bash
# Builds web/public/m5_emu.avm: the m5_emu library pack (no start module). It is loaded before
# atomvmlib.avm and the app, so its modules (m5_display, gpio, ...) shadow any same-named ones.
set -euo pipefail
cd "$(dirname "$0")/../m5_emu"
rebar3 compile
# packbeam_api (atomvm_packbeam 0.7.4, pulled by atomvm_rebar3_plugin) has no `lib` option; a pack
# without a start module is start_module => undefined. packbeam still flags any module exporting
# start/0 as an entrypoint, so the listing below fails the build if one slips in.
erl -noshell -pa _build/default/plugins/*/ebin -eval '
  Beams = filelib:wildcard("_build/default/lib/m5_emu/ebin/*.beam"),
  ok = packbeam_api:create("../web/public/m5_emu.avm", Beams,
                           #{prune => false, start_module => undefined, include_lines => true}),
  Elements = packbeam_api:list("../web/public/m5_emu.avm"),
  Entry = [packbeam_api:get_element_name(E) || E <- Elements, packbeam_api:is_entrypoint(E)],
  io:format("wrote web/public/m5_emu.avm (~p elements)~n", [length(Elements)]),
  case Entry of
    [] -> halt(0);
    _ -> io:format(standard_error, "unexpected start modules: ~p~n", [Entry]), halt(1)
  end.'

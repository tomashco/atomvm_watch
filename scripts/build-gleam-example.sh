#!/usr/bin/env bash
# Builds a Gleam example into examples/<app>/<app>.avm, ready for the emulator page or the watch.
#
#   scripts/build-gleam-example.sh <app>          # e.g. gleam_hello, gleam_scenes
#
# Gleam compiles the app and gleam_stdlib. The Erlang libraries the app calls with @external
# (atomvm_m5, avm_scene, m5_scene) are rebar3 projects, which Gleam's git and path dependencies do
# not accept, so scripts/gleam_libs builds them and this script packs everything with packbeam.
# Modules the start module can't reach are pruned, which keeps gleam_stdlib's share small.
set -euo pipefail
app="${1:?usage: build-gleam-example.sh <app>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/examples/$app"
[ -f "$dir/gleam.toml" ] || { echo "no gleam.toml in examples/$app" >&2; exit 1; }

(cd "$dir" && gleam build --target erlang)

libs="$root/scripts/gleam_libs"
mkdir -p "$libs/_checkouts"
ln -sfn "$root/m5_scene" "$libs/_checkouts/m5_scene"
(cd "$libs" && rebar3 compile)

out="$dir/$app.avm"
erl -noshell -pa "$libs"/_build/default/plugins/*/ebin -eval '
  [App, Out, GleamDir, LibsDir] = init:get_plain_arguments(),
  Gleam = [filelib:wildcard(filename:join([GleamDir, D, "ebin", "*.beam"])) || D <- [App, "gleam_stdlib"]],
  %% rebar3 builds checkout dependencies (m5_scene) under checkouts/, the others under lib/.
  Libs = [filelib:wildcard(filename:join([LibsDir, Kind, D, "ebin", "*.beam"]))
          || {Kind, D} <- [{"lib", "atomvm_m5"}, {"lib", "avm_scene"}, {"checkouts", "m5_scene"}]],
  [] =:= [D || {D, []} <- lists:zip(["atomvm_m5", "avm_scene", "m5_scene"], Libs)]
    orelse error({missing_beams, [D || {D, []} <- lists:zip(["atomvm_m5", "avm_scene", "m5_scene"], Libs)]}),
  Beams = lists:append(Gleam ++ Libs),
  ok = packbeam_api:create(Out, Beams, #{prune => true, start_module => list_to_atom(App)}),
  N = length(packbeam_api:list(Out)),
  io:format("wrote ~s (~p modules, ~p bytes)~n", [Out, N, filelib:file_size(Out)]),
  halt().' -extra "$app" "$out" "$dir/build/dev/erlang" "$libs/_build/default"

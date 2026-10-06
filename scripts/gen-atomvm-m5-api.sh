#!/usr/bin/env bash
# Pins the public API of atomvm_m5 at ATOMVM_M5_COMMIT into m5_emu/test/atomvm_m5_api.txt
# (one Module:Fun/Arity per line). The drift test then checks that m5_emu exports all of it.
#
# Two sources, unioned:
#   1. exports of the Erlang stub modules in src/ (m5, m5_display, m5_power, m5_power_axp192, m5_rtc, m5_speaker);
#   2. the NIF tables in nifs/*.cc. The NIF table is the real surface: it holds functions the stubs
#      do not export (m5_speaker:play_raw_*, m5_imu:get_accel/0 ...) and modules with no stub at all
#      (m5_btn_*, m5_imu, m5_in_i2c, m5_ex_i2c). Each table is paired with every MODULE_*PREFIX
#      "mod:" defined in its file.
# Needs curl and erl. Run from anywhere; run it again after bumping ATOMVM_M5_COMMIT.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. ./versions.env
: "${ATOMVM_M5_COMMIT:?missing in versions.env}"
RAW="https://raw.githubusercontent.com/pguyot/atomvm_m5/$ATOMVM_M5_COMMIT"
API="https://api.github.com/repos/pguyot/atomvm_m5/contents"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for m in m5 m5_display m5_power m5_power_axp192 m5_rtc m5_speaker; do
  curl -fsSL "$RAW/src/$m.erl" -o "$TMP/$m.erl"
  erl -noshell -eval "
    {ok, F} = epp:parse_file(\"$TMP/$m.erl\", []),
    Ex = lists:append([L || {attribute, _, export, L} <- F]),
    [io:format(\"$m:~s/~p~n\", [N, A]) || {N, A} <- Ex], halt()."
done > "$TMP/api.txt"

for f in $(curl -fsSL "$API/nifs?ref=$ATOMVM_M5_COMMIT" | grep -o '"name": *"[^"]*\.cc"' | sed 's/.*: *"//; s/"//'); do
  curl -fsSL "$RAW/nifs/$f" -o "$TMP/$f"
  mods=$(grep -o '#define MODULE[A-Z_]*PREFIX "[a-z_0-9]*:"' "$TMP/$f" | sed 's/.*"\(.*\):"/\1/')
  funs=$(grep -o '"[a-z_0-9]*/[0-9]*"' "$TMP/$f" | tr -d '"')
  for mod in $mods; do for fn in $funs; do echo "$mod:$fn"; done; done
done >> "$TMP/api.txt"

sort -u "$TMP/api.txt" > m5_emu/test/atomvm_m5_api.txt
echo "$(wc -l < m5_emu/test/atomvm_m5_api.txt | tr -d ' ') functions in $(cut -d: -f1 m5_emu/test/atomvm_m5_api.txt | sort -u | wc -l | tr -d ' ') modules"

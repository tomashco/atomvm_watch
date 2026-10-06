#!/usr/bin/env bash
# Builds atomvmlib.avm (the Erlang/Elixir standard library archive) from AtomVM source at
# ATOMVM_VERSION. The wasm release assets ship without it. Only the libs target is built, not the
# native VM. Needs cmake, ninja, erlang and elixir (provided by devenv).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ATOMVM_VERSION:?set by devenv (versions.env)}"
SRC=vendor/AtomVM-src
OUT_WEB=web/public/atomvm/atomvmlib.avm
OUT_VENDOR=vendor/atomvm/atomvmlib.avm
STAMP=vendor/atomvm/atomvmlib.version

if [ -f "$OUT_WEB" ] && [ -f "$OUT_VENDOR" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$ATOMVM_VERSION" ]; then
  echo "atomvmlib.avm ${ATOMVM_VERSION} already built"
  exit 0
fi

if [ ! -d "$SRC/.git" ] || [ "$(git -C "$SRC" describe --tags --exact-match 2>/dev/null)" != "$ATOMVM_VERSION" ]; then
  rm -rf "$SRC"
  git clone --quiet --depth 1 --branch "$ATOMVM_VERSION" https://github.com/atomvm/AtomVM "$SRC"
fi

cmake -S "$SRC" -B "$SRC/build-libs" -G Ninja -DAVM_DISABLE_JIT=ON -DAVM_BUILD_RUNTIME_ONLY=ON >/dev/null
cmake --build "$SRC/build-libs" --target atomvmlib

mkdir -p "$(dirname "$OUT_WEB")" "$(dirname "$OUT_VENDOR")"
cp "$SRC/build-libs/libs/atomvmlib.avm" "$OUT_WEB"
cp "$SRC/build-libs/libs/atomvmlib.avm" "$OUT_VENDOR"
echo "$ATOMVM_VERSION" > "$STAMP"
echo "atomvmlib.avm ${ATOMVM_VERSION} ready ($(wc -c < "$OUT_WEB" | tr -d ' ') bytes)"

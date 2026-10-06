#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ATOMVM_VERSION:?set by devenv (versions.env)}"
BASE="https://github.com/atomvm/AtomVM/releases/download/${ATOMVM_VERSION}"
fetch() { # $1 asset name, $2 destination path
  local name="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ] && [ -f "$dest.sha256" ]; then return 0; fi
  curl -fsSL "$BASE/$name" -o "$dest"
  curl -fsSL "$BASE/$name.sha256" -o "$dest.sha256"
  (cd "$(dirname "$dest")" && sed "s#$name#$(basename "$dest")#" "$(basename "$dest").sha256" | shasum -a 256 -c -)
}
fetch "AtomVM-web-${ATOMVM_VERSION}.mjs"  web/public/atomvm/AtomVM.mjs
fetch "AtomVM-web-${ATOMVM_VERSION}.wasm" web/public/atomvm/AtomVM.wasm
fetch "AtomVM-node-${ATOMVM_VERSION}.mjs"  vendor/atomvm/AtomVM.mjs
fetch "AtomVM-node-${ATOMVM_VERSION}.wasm" vendor/atomvm/AtomVM.wasm
echo "AtomVM ${ATOMVM_VERSION} wasm builds ready"

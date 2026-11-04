#!/usr/bin/env bash
# Mirrors the firmware releases listed in firmware/<board>/runtimes.json into <out> (the site's
# firmware/ directory), for the page's runtime selector:
#
#   <out>/<version>/manifest-<board>.json and its image, one directory per listed release
#   <out>/manifest-<board>.json and its image, the first (recommended) entry, as before
#   <out>/runtimes-<board>.json, [{version, description, manifest}] with manifest relative to <out>
#
#   scripts/mirror-firmware.sh m5stickc_plus2 web/dist/firmware      # needs gh and GH_TOKEN
#
# Release downloads send no CORS headers, which COEP (require-corp) needs, hence the mirror.
set -euo pipefail
board="${1:?usage: mirror-firmware.sh <board> <out>}"
out="${2:?usage: mirror-firmware.sh <board> <out>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
list="$root/firmware/$board/runtimes.json"
manifest="manifest-$board.json"
mkdir -p "$out"

versions=$(python3 -c 'import json,sys; print("\n".join(r["version"] for r in json.load(open(sys.argv[1]))))' "$list")
[ -n "$versions" ] || { echo "$list lists no runtimes" >&2; exit 1; }
for v in $versions; do
  dir="$out/$v"
  mkdir -p "$dir"
  gh release download "firmware-$board-v$v" --repo "$GITHUB_REPOSITORY" --pattern "$manifest" --dir "$dir" --clobber
  img=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parts"][0]["path"])' "$dir/$manifest")
  gh release download "firmware-$board-v$v" --repo "$GITHUB_REPOSITORY" --pattern "$img" --dir "$dir" --clobber
  test -f "$dir/$img"
done

first=$(head -n1 <<<"$versions")
cp "$out/$first"/* "$out/"

python3 - "$list" "$manifest" "$out/runtimes-$board.json" <<'PY'
import json, sys
src, manifest, dst = sys.argv[1:]
runtimes = [{"version": r["version"], "description": r["description"], "manifest": f'{r["version"]}/{manifest}'}
            for r in json.load(open(src))]
json.dump(runtimes, open(dst, "w"), indent=2)
PY
ls -lR "$out"

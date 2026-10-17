#!/usr/bin/env bash
# Usage (inside espressif/idf:v5.5.1 with OTP+Elixir installed):
#   firmware/build.sh <board> <atomvm_version> <atomvm_m5_commit> <out_dir>
set -euo pipefail
BOARD=$1; ATOMVM_VERSION=$2; M5_COMMIT=$3; mkdir -p "$4"; OUT=$(realpath "$4")
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-/tmp/atomvm-build}; mkdir -p "$WORK"; cd "$WORK"
[ -d AtomVM ] || git clone --depth 1 --branch "$ATOMVM_VERSION" https://github.com/atomvm/AtomVM.git
cd AtomVM
# 1. Host build of the Erlang/Elixir boot libraries (needed by mkimage for boot.avm).
mkdir -p build && (cd build && cmake .. -DAVM_DISABLE_SMP=OFF >/dev/null && make -C libs -j"$(nproc)")
# 2. Add atomvm_m5 as an ESP-IDF component and patch it.
COMP=src/platforms/esp32/components/atomvm_m5
[ -d "$COMP" ] || git clone https://github.com/pguyot/atomvm_m5.git "$COMP"
(cd "$COMP" && git checkout -q -f "$M5_COMMIT" && git reset -q --hard "$M5_COMMIT")
for p in "$HERE/$BOARD/patches/"*.patch; do (cd "$COMP" && git apply --3way "$p"); done
# 3. Board partition table replaces the Elixir one (AtomVM's CMake selects partitions-elixir.csv when Elixir support is on).
cp "$HERE/$BOARD/partitions.csv" src/platforms/esp32/partitions-elixir.csv
# 4. Build with ESP-IDF.
cd src/platforms/esp32
# shellcheck disable=SC1091
. "$IDF_PATH/export.sh"
rm -rf build sdkconfig
export SDKCONFIG_DEFAULTS="sdkconfig.defaults;$HERE/$BOARD/sdkconfig.$BOARD"
idf.py -DATOMVM_ELIXIR_SUPPORT=on set-target esp32
# set-target writes sdkconfig from the defaults above; fail fast if the 8 MB override was lost.
grep -q CONFIG_ESPTOOLPY_FLASHSIZE_8MB=y sdkconfig
idf.py -DATOMVM_ELIXIR_SUPPORT=on build
./build/mkimage.sh
ls build/*.img   # the image name is unverified: this listing shows the real one if the cp below fails
VERSION=${FW_VERSION:-dev}
IMG="AtomVM-$BOARD-$VERSION.img"
cp build/atomvm-esp32-elixir.img "$OUT/$IMG"
(cd "$OUT" && sha256sum "$IMG" > "$IMG.sha256")
sed -e "s/@VERSION@/$VERSION/" -e "s/@ATOMVM@/$ATOMVM_VERSION/" -e "s/@IMG@/$IMG/" "$HERE/$BOARD/manifest.template.json" > "$OUT/manifest-$BOARD.json"
(cd "$OUT" && sha256sum "manifest-$BOARD.json" > "manifest-$BOARD.json.sha256")
echo "built $OUT/$IMG"

#!/usr/bin/env bash
# Builds the emulator page and copies it into m5_emu_mix/priv/web (served by `mix m5.emulate`).
set -euo pipefail
cd "$(dirname "$0")/../web"
pnpm build
rm -rf ../m5_emu_mix/priv/web
mkdir -p ../m5_emu_mix/priv
cp -RL dist ../m5_emu_mix/priv/web
# vite copies public/ into dist/ already; this is a safety net for the runtime image.
cp public/m5_emu.avm ../m5_emu_mix/priv/web/

# 06 — References and open questions

## Projects we build on

| Project | Link | Role here |
|---------|------|-----------|
| AtomVM | https://github.com/atomvm/AtomVM | The VM: ESP32 firmware and the `emscripten` wasm build the emulator runs on |
| atomvm_m5 | https://github.com/pguyot/atomvm_m5 | The app API (M5Unified/M5GFX NIFs); `m5_emu` mirrors its modules |
| M5Unified / M5GFX | https://github.com/m5stack/M5Unified · https://github.com/m5stack/M5GFX | Behaviour `m5_emu` copies: button class, drawing and text semantics |
| LovyanGFX | https://github.com/lovyan03/LovyanGFX | Source of the 6x8 "Font0" glyphs used by the renderer |
| exatomvm | https://github.com/atomvm/exatomvm | Mix tasks: pack `.avm`, flash from the terminal |
| atomvm_packbeam | https://github.com/atomvm/atomvm_packbeam | `.beam` → `.avm` packer (`m5_emu.avm` is packed with `--lib`) |
| atomvm_rebar3_plugin | https://github.com/atomvm/atomvm_rebar3_plugin | Builds `m5_emu` and Erlang apps |
| esptool-js | https://github.com/espressif/esptool-js | Web Serial flashing in the installer |
| coi-serviceworker | https://github.com/gzuidhof/coi-serviceworker | COOP/COEP headers on GitHub Pages, needed for SharedArrayBuffer |
| M5StickC Plus2 docs | https://docs.m5stack.com/en/core/StickC-Plus2 | First board |

## Inspiration

| Project | Link | Why |
|---------|------|-----|
| Bangle.js App Loader | https://github.com/espruino/BangleApps | The UX and app-store model |
| Espruino emulator | https://github.com/espruino/EspruinoWebIDE | "VM in wasm + canvas" |
| atomvm-web-tools | https://github.com/petermm/atomvm-web-tools | Browser flashing of AtomVM via Web Serial |

## Settled (verified 2026-10-03)

- The wasm build supports JS↔Erlang messaging (`Module.cast` / `Module.call`, `emscripten:run_script/2`)
  but has no ports.
- Module shadowing: the first loaded pack that contains a module wins.
- `atomvm:add_avm_pack_binary/2`, `esp:partition_read/3`, `esp:partition_write/3`,
  `esp:partition_erase_range/3` exist, which milestone 2 builds on.
- AtomVM 0.7 flash layout: VM at `0x10000`, `boot.avm` at `0x1D0000`, `main.avm` at `0x250000`.
- One `ATOMVM_VERSION` (`v0.7.0-beta.0`) keeps the wasm VM, the firmware and compiled apps
  compatible.

## Open questions

1. Is `run_script` fast enough for apps that draw a lot, or do we need the ring buffer?
2. How close is the 6x8 text rendering to the device once compared against photos?
3. How will milestone 2's installer find and claim free slots in `apps` (index format, slot size)?
4. Wi‑Fi or BLE for phone installs, and when? Mainline AtomVM has no BLE API.

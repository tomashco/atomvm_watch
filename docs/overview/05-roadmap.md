# 05 — Roadmap

Each milestone is useful on its own.

## Milestone 1: emulator and installer, one app (in progress)

- `m5_emu` runs `atomvm_m5` apps on AtomVM's wasm build in the browser.
- The web page loads an `.avm`, runs it on a 135×240 canvas with buttons, sound and LED, and
  flashes the runtime and the app to the watch over Web Serial.
- Firmware image (AtomVM + `atomvm_m5`) built in CI, with the 8 MB partition table that reserves
  the `apps` partition.
- `mix m5.emulate` for the Elixir dev loop.
- Done when `examples/clock` runs identically in the emulator and on the watch, and both
  installs work from the page.

Spec: `docs/superpowers/specs/2026-10-03-atomvm-watch-design.md`.
Plan: `docs/superpowers/plans/2026-10-03-milestone-1-emulator-installer.md`.

## Milestone 2: on-device app loader

- Launcher app in `main.avm`: lists, starts and switches apps.
- Apps stored in the `apps` partition and loaded at runtime with `atomvm:add_avm_pack_binary/2`.
- Installer writes an app to a free slot without reflashing the others.
- Emulator models the `apps` partition.

## Milestone 3: more boards and peripherals

- More M5 boards (Core2 first) as new board profiles and firmware directories.
- IMU, RTC, battery over I²C in the emulator.
- A Gleam example app.
- Hosted gallery of CI-built apps with **Try** (emulator) and **Install** buttons.

## Backlog (no milestone yet)

- Wi‑Fi install: the launcher serves HTTP so a phone can install apps without USB.
- Bluetooth install: a BLE component for AtomVM plus a Web Bluetooth loader. Mainline AtomVM
  has no BLE API, so this is the largest single piece of work.
- Hosted compile endpoint, for editing in the browser.
- Mirroring the real watch's screen in the page.
- Native emulation: `atomvm_m5`'s NIFs compiled against M5GFX's SDL backend (see `03-emulator.md`).
- ESP32 watches that aren't M5 (T‑Watch, Watchy e‑paper).

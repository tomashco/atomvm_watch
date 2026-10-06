# 01 — Vision

## Goal

Do for AtomVM watches what Bangle.js does for its nRF52 watch:

- a web page you open on your laptop (and later your phone),
- one click to install an app on the watch,
- a browser emulator that runs the same app before you flash it,
- later, a catalogue of apps and an on-device loader that holds several of them,

but with apps written in **Elixir, Gleam or Erlang** and running on the **BEAM (AtomVM)**.

Boards are described by data (a board profile), so adding a watch does not change the emulator,
the installer or the apps. The first board is the M5StickC Plus 2. Other M5 devices come next,
since `atomvm_m5` already covers them.

## The Bangle.js analogy

| Bangle.js                                                     | atomvm_watch                                                              |
| ------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Espruino JS interpreter in firmware                           | AtomVM + `atomvm_m5` component in firmware                                |
| App = JS source files written to flash storage                | App = one `.avm` written to the `main.avm` partition (milestone 1), or to an `apps` slot loaded at runtime by a launcher (milestone 2) |
| App Loader web page (Web Bluetooth)                           | Same page as the emulator, installs over USB with Web Serial (`esptool-js`) |
| `apps.json` metadata + GitHub repo                            | Later: hosted gallery of CI-built `.avm` apps                             |
| Emulator = Espruino compiled with Emscripten, LCD on a canvas | Emulator = AtomVM's own wasm build running the app, with `m5_emu` standing in for `atomvm_m5` and drawing to a canvas |

## The one big difference: compiled, not interpreted

Bangle pushes **source** and the watch interprets it. AtomVM runs **compiled BEAM bytecode**
packed into `.avm` files. There is no Erlang/Elixir compiler that runs on the device, and no
realistic one in the browser either (`erlc` is BEAM-hosted; Gleam's WASM compiler only reaches
Erlang *source* on the Erlang target).

Consequences:

1. Compilation always happens off-watch: locally (`mix` / `rebar3` / `gleam` + packbeam), or in
   CI for a future gallery.
2. The page moves `.avm` **binaries**, never source. This is fine: it's what the Bangle loader
   effectively does too (it fetches prebuilt app files from GitHub Pages).
3. The dev loop is local: `mix m5.emulate` re-packs on save and reloads the emulator.

## The app API

Apps call `atomvm_m5` (`m5`, `m5_display`, `m5_btn_*`, `m5_speaker`, `m5_power`, …) directly,
with no abstraction layer and no platform conditionals. On the watch these are `atomvm_m5`'s NIFs;
in the browser `m5_emu.avm` is loaded first and provides the same modules. One `.avm` runs in
both places.

## Non-goals (for now)

- nRF52 watches (PineTime, Bangle itself): AtomVM has no nRF52 port.
- ESP32 watches that aren't M5 (LilyGO T‑Watch, Watchy, …): they need a board library other than
  `atomvm_m5`. Not designed for yet.
- Wi‑Fi and Bluetooth installs, AtomGL, an in-browser compiler. See `05-roadmap.md`.

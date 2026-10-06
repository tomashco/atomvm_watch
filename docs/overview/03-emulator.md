# 03 — Emulator

## Definition

"Emulator" here means: **AtomVM itself running in the browser tab (its official wasm build), with
the app's `atomvm_m5` calls rendered on a canvas and browser input fed back as button presses.**
Nothing runs on a device or a server, and no chip is emulated. Same model as the Bangle.js
emulator (Espruino built with Emscripten + canvas), with the BEAM instead of a JS interpreter.

```
┌──────────────────────── browser tab ────────────────────────┐
│                                                             │
│   AtomVM wasm (worker)              canvas (watch screen)   │
│   ┌─────────────────────────┐       ┌───────────────┐       │
│   │ app .avm                │       │               │       │
│   │   ↓ m5_display calls    │─JSON─▶│  m5emu.ts     │       │
│   │ m5_emu.avm              │◀─str──│  input.ts     │       │
│   └─────────────────────────┘       └───────────────┘       │
│    run_script / Module.cast               ▲                 │
│                                   clicks / keys             │
└─────────────────────────────────────────────────────────────┘
```

## Runtime

- AtomVM ships an `emscripten` platform with prebuilt `AtomVM-web-<ver>.wasm` and `.mjs`.
  `scripts/fetch-atomvm.sh` downloads the build matching `ATOMVM_VERSION`, checks its sha256 and
  puts it under `web/public/atomvm/`. The page never modifies it. The release has no stdlib, so
  `scripts/build-atomvmlib.sh` builds `atomvmlib.avm` from AtomVM source at the same version; it
  loads after `m5_emu.avm` and before the app.
- Erlang to JS: `emscripten:run_script(Script, [main_thread, async])`.
- JS to Erlang: `Module.cast(name, string)`, delivered to a registered process as
  `{emscripten, {cast, Bin}}`.
- We don't use Popcorn: 0.3 ran on AtomVM, but 0.4 moved to OTP on wasm.

## `m5_emu` (Erlang side)

Erlang only, so Elixir and Gleam apps use it unchanged.

- `m5`: `begin_/1` starts the emulator processes and reads the board values from the page;
  `get_board/0` returns the profile's atom (`stick_cplus2`); `update/0` steps the buttons.
- `m5_display`: the drawing and text subset of M5GFX, plus rotation, brightness, sleep/wake,
  `start_write`/`end_write` batching.
- `m5_btn_a` / `b` / `c` / `pwr` / `ext`: all 22 functions of the `atomvm_m5` button API.
- `m5_speaker`: `tone/2,3,4`, volume, `is_playing/0` (tracked locally, no round trip).
- `m5_speaker`: also `play_raw_u8/s8/s16`, raw PCM played by the page through WebAudio.
- `m5_rtc`: the host's UTC clock plus an offset that `set_datetime/date/time` adjust.
- `m5_power`: battery level from the page's slider, not charging.
- `gpio`: a shim for pin 19 (red LED) only.

Processes: `m5_emu_display` owns display state and the command buffer; `m5_emu_input` (registered)
receives `a:down`, `pwr:up`, `batt:73`, … and holds raw button levels; `m5_emu_btn` is a pure port
of M5Unified's `Button_Class`, unit-tested on plain OTP.

## Page (JS side)

- **Renderer:** a 135×240 framebuffer drawn at 3×. It follows M5GFX's rules: rotation 0–3, text
  cursor advance and wrap for `print`/`println`, `set_text_size` scaling, sleep blanks the screen,
  brightness dims it. Font: LovyanGFX's 6x8 "Font0" glyphs.
- **Input:** on-screen buttons A, B and Power (keys `A`, `B`, `P`), and a battery slider.
- **Audio:** a WebAudio square wave for tones, and an audio buffer for raw PCM.
- **Loading apps:** drag-and-drop, a file picker, or `?avm=<url>`. The last app is kept in
  IndexedDB, so a reload restarts it.
- **Errors:** a crashed VM shows the last stderr lines and a restart button. Unsupported calls
  are logged once per function.

## Dev loop

`mix m5.emulate` packs the project, serves the page with the right headers, opens
`?avm=http://localhost:<port>/app.avm`, and re-packs on file changes. The page polls `/__version`
(bumped after each successful pack) and reloads the VM when it changes.

## Known gaps and future direction

- Text rendering and timing are close to the device, not exact. Golden frames are compared
  against photos of the watch.
- Calling `run_script` for every draw may be too slow for loops that draw a lot. It's benchmarked
  early (1000 `fill_rect`/s), with a shared binary ring buffer as the fallback.
- Not planned yet: compile `atomvm_m5`'s NIFs against M5GFX's SDL backend into a forked wasm
  build, for pixel-exact rendering and the real button class. Apps and the page would not change,
  because they only see the `atomvm_m5` API either way. Revisit when emulator drift becomes a
  real problem.

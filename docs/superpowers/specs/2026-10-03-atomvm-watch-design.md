# atomvm_watch — emulator and installer for AtomVM watches, first board M5StickC Plus 2

Date: 2026-10-03
Status: approved for planning (milestone 1)

## 1. Goal

`atomvm_watch` is a platform for running AtomVM apps on ESP32 watches: write apps in Elixir,
Erlang or Gleam, run them in a browser emulator, and install them on the real watch from the same
web page, in the spirit of the Bangle.js app loader. Boards are described by data (a board
profile) so that adding a watch later does not change the emulator, the installer or the apps.
The first and only board in milestone 1 is the M5StickC Plus 2.

Milestone 1 (this spec): one app at a time. The emulator runs it, the page flashes the runtime
and the app to a watch over USB, and an Elixir example proves the full loop.

Milestone 2 (separate spec, later): an on-device loader that lists, starts and receives multiple
apps, and an installer that adds apps without reflashing the others.

Out of scope for milestone 1: IMU, battery reading, HOLD pin, microphone, IR, Wi-Fi,
AtomGL/avm_scene display stack, a C/Emscripten port of the NIFs (see section 11).

## 2. Context and facts the design relies on

Verified against upstream sources on 2026-10-03:

- AtomVM ships an `emscripten` platform with prebuilt `AtomVM-web-<ver>.wasm` and `.mjs`.
  It needs SharedArrayBuffer, hence COOP and COEP headers. JS to Erlang messaging is
  `Module.cast(name, string)` and `Module.call(name, string)`, delivered to a registered process
  as `{emscripten, {cast, Bin}}` / `{emscripten, {call, Promise, Bin}}`. Erlang to JS is
  `emscripten:run_script(Script, [main_thread, async])`.
- The wasm platform's `sys_create_port` returns NULL: no ports exist in the browser VM.
- AtomVM resolves a module from the first loaded `.avm` pack that contains it (packs are
  appended in load order). Loading our pack before the app's pack shadows same-named modules.
- AtomVM's wasm release ships no standard library, so `atomvmlib.avm` (the `emscripten` build's
  libs target) is built from AtomVM source at `ATOMVM_VERSION` by `scripts/build-atomvmlib.sh`.
  It is loaded between `m5_emu.avm` and the app; the first pack wins on name conflicts, so our
  `gpio` shim still shadows the one in atomvmlib. The smoke and e2e tests prove this.
- `atomvm_m5` (pguyot) wraps M5Unified 0.2.10 and M5GFX 0.2.17 as NIFs for the ESP32 build:
  modules `m5`, `m5_display`, `m5_btn_{a,b,c,pwr,ext}`, `m5_speaker`, `m5_power`,
  `m5_power_axp192`, `m5_rtc`, `m5_imu`, `m5_i2c`. Its `src/*.erl` are stubs that throw
  `nif_error`; the NIF collection takes precedence on the device. M5GFX autodetects the
  StickC Plus 2 by chip package. `m5:get_board/0` lacks a `board_M5StickCPlus2` case.
- Popcorn 0.3 runs on AtomVM; Popcorn 0.4 moved to OTP-on-wasm. We use AtomVM's wasm build
  directly and do not depend on Popcorn.
- ESP32 flash layout since AtomVM 0.7: bootloader `0x1000`, partition table `0x8000`,
  VM `0x10000`, `boot.avm` `0x1D0000`, `main.avm` `0x250000` (1 MB). The StickC Plus 2 has
  8 MB flash and 2 MB PSRAM, so about 4.6 MB is unused by the default table.
- `esp:partition_read/3`, `partition_write/3`, `partition_erase_range/3` and
  `atomvm:add_avm_pack_binary/2` exist, which milestone 2 will build on.
- Board pins: display ST7789V2 135x240 on MOSI 15, CLK 13, DC 14, RST 12, CS 5, BL 27;
  buttons A 37, B 39, C/power 35; HOLD 4; red LED and IR 19; buzzer 2; I2C 21/22; battery ADC 38.
  M5Unified handles all of these; the pins matter only for documentation here.

## 3. Architecture

Four deliverables share one repository:

1. `boards/<id>/board.json` — the board profile: id and display name, screen width, height and
   native rotation, physical buttons (id, label, keyboard shortcut, position on the device
   image), peripherals present (speaker, led, battery), the device image (SVG), the `m5` board
   atom, the flash chip id and the firmware manifest URL. Milestone 1 ships
   `boards/m5stickc_plus2/`.
2. `m5_emu/` — an Erlang library whose modules have the exact names and arities of `atomvm_m5`
   and are implemented for the `emscripten` platform by forwarding to JavaScript. Packed as
   `m5_emu.avm`. Board-specific values (screen size, board atom, which buttons exist) are
   passed in at `m5:begin_/1` time by the page from the profile (the `m5emu.boardReady()` call
   and the `board:<atom>:<w>:<h>` cast, see 4.1); the library has no board constants.
3. `web/` — a static page: the AtomVM wasm VM, the display renderer and device controls, and a
   Web Serial installer, all configured from the selected board profile. Hosted on GitHub
   Pages, also served locally.
4. `firmware/<board>/` — partition table, `sdkconfig.defaults` and a CI workflow producing the
   ESP32 runtime image (AtomVM + `atomvm_m5` component) that the installer flashes for that
   board.

Plus `m5_emu_mix/` (a `mix m5.emulate` task) and `examples/clock/` (the reference Elixir app).

Scope guard: milestone 1 has exactly one profile and no board picker UI beyond reading
`?board=` from the URL (default `m5stickc_plus2`). The profile exists so the second board is a
data change, not a redesign. Non-M5 watches would additionally need a board library other than
`atomvm_m5`; that is out of scope and not pre-designed.

The app-facing API is `atomvm_m5`, unchanged. An app compiles against `atomvm_m5`'s stub
modules, runs on the device against the NIFs, and runs in the browser against `m5_emu`, which is
loaded first and shadows the stubs. Apps never contain platform conditionals.

Data flow in the browser:

```
app .avm ──────┐
atomvmlib.avm ─┤  (load order: m5_emu.avm, atomvmlib.avm, app)
m5_emu.avm ────┴─> AtomVM-web.wasm (worker thread)
                 │  emscripten:run_script("m5emu.exec([...])")   drawing, tone, led
                 ▼
            web/src/m5emu.js (main thread) ──> <canvas>, WebAudio, DOM
                 ▲
                 │  Module.cast("m5_emu_input", "a:down")        buttons, battery
            on-screen buttons / keyboard
```

## 4. `m5_emu` — Erlang side

Rebar3 library, Erlang only, so Elixir and Gleam apps use it unchanged. Target AtomVM version
is pinned in one place (`ATOMVM_VERSION` in `versions.env`, next to the `atomvm_m5` commit) and
must match the wasm binary, `atomvmlib.avm` and the firmware.

### 4.1 Module surface

Same module names as `atomvm_m5`. Milestone 1 implements:

- `m5`: `begin_/1` (starts the emulator processes, resets display state, registers
  `m5_emu_input`, calls `m5emu.boardReady()` and waits for the page's `board:<atom>:<w>:<h>` cast
  carrying the board profile values; AtomVM's wasm build has no VM environment variables),
  `get_board/0` (returns the profile's board atom, `stick_cplus2` for the first board, matching `atomvm_m5`'s `stick_cplus` naming),
  `update/0` (drains input events, advances button state machines).
- `m5_display`: the drawing and text subset listed in 4.3, plus `width/0`, `height/0`,
  `get_rotation/0`, `set_rotation/1`, `set_brightness/1`, `sleep/0`, `wakeup/0`,
  `start_write/0`, `end_write/0`, `set_epd_mode/1` (no-op), `power_save*` (no-op).
- `m5_btn_a`, `m5_btn_b`, `m5_btn_c`, `m5_btn_pwr`, `m5_btn_ext`: all 22 functions of the
  `atomvm_m5` button API. `m5_btn_c` and `m5_btn_ext` exist for API completeness and never
  press (the Plus 2 has no button C in M5Unified's model; its third physical button is `pwr`).
- `m5_speaker`: `is_enabled/0` (true), `set_volume/1`, `tone/2,3,4`, `is_playing/0`, `stop/0`.
- `m5_power`: `get_battery_level/0` (value last sent by the page's slider, default 100),
  `is_charging/0` (false), `get_type/0` (`unknown`). Other functions return `ok` or
  `{error, unsupported}` per the stub's spec.

Functions of `atomvm_m5` not listed above are present and return `{error, unsupported}` or
throw `unsupported` where the return type leaves no room, so an app sees a clear error instead
of `undef`. A generated check in the test suite compares our export lists with the pinned
`atomvm_m5` revision and fails on drift.

### 4.2 Processes

- `m5_emu_display` (gen_server): owns display state (rotation, cursor, text size, colors,
  sleep flag, brightness) and the command buffer. Public functions in `m5_display` are thin
  calls into it, so state is consistent across app processes.
- `m5_emu_input` (gen_server, registered under that name): receives
  `{emscripten, {cast, Bin}}` where `Bin` is `<<"a:down">>`, `<<"pwr:up">>`,
  `<<"batt:73">>`; stores raw button levels with monotonic timestamps and the battery value.
- Button state: one `m5_emu_btn` record per button, a pure functional port of M5Unified's
  `Button_Class` (debounce 10 ms, hold 500 ms defaults, click counting, the `was_*` edge flags
  that are true for exactly one `update/0` cycle). `m5:update/0` reads raw levels from
  `m5_emu_input` and steps every record. Pure functions make this unit-testable on plain OTP.

### 4.3 Display command protocol

`m5_display` calls append tuples to the buffer in `m5_emu_display`. Outside a
`start_write/end_write` pair every call flushes immediately; inside, `end_write` flushes once.
A flush encodes the buffer as a JSON array and runs
`m5emu.exec(<json>)` through `emscripten:run_script/2` with `[main_thread, async]`.

Commands (names mirror M5GFX):
`fill_screen c`, `fill_rect x y w h c`, `draw_rect x y w h c`, `draw_pixel x y c`,
`draw_line x0 y0 x1 y1 c`, `draw_fast_vline`, `draw_fast_hline`, `fill_circle`, `draw_circle`,
`fill_round_rect`, `draw_round_rect`, `draw_string s x y`, `draw_center_string s x y`,
`draw_right_string s x y`, `print s`, `println s`, `set_cursor x y`, `set_text_size sx sy`,
`set_text_color fg [bg]`, `set_color c`, `set_rotation r`, `set_brightness b`, `sleep`,
`wakeup`, `clear`.

Colors are normalized to RGB888 integers before encoding; `m5_display` accepts the same
forms as `atomvm_m5` (`{R,G,B}` tuples, RGB888 integers, and RGB565 integers via the
`set_raw_color/1` path).

Strings are sent as UTF-8; the renderer draws what the 6x8 font covers and a box for the rest.

### 4.4 Speaker, LED, power

`m5_speaker:tone(Freq, Ms)` sends `tone f ms vol`; `is_playing/0` is derived from the end
time recorded locally, so it needs no round trip. The red LED is driven by apps through
`gpio` on the device; in the emulator a `gpio` shim module covers `set_pin_mode/2`,
`digital_write/2` and `digital_read/1` for pin 19 only, forwarding `led on|off`. Other pins
return `{error, unsupported}`. Battery level arrives as `batt:N` casts.

Added after milestone 1 shipped, so that atomvm_m5's `how_to_use` example runs:
`m5_speaker:play_raw_u8/s8/s16` (all arities, NIF defaults: 44100 Hz, mono, repeat 1; repeat 0
loops until `stop/0`) sends `play_raw fmt base64 rate stereo repeat vol`, which the page plays
through a WebAudio buffer; `is_playing/0` covers it. `m5_rtc` is enabled and emulated from the
host's UTC clock plus an offset that `set_datetime/date/time` adjust, so a set time keeps ticking.

## 5. `web/` — browser side

Vite project, plain TypeScript, no framework. Files:

- `index.html`, `src/main.ts`: page layout, loads `coi-serviceworker.js` first so COOP/COEP
  are in place before the VM module is fetched.
- `src/board.ts`: loads `boards/<id>/board.json` (from `?board=`, default `m5stickc_plus2`),
  validates it, and hands it to the renderer (screen size), input (button list and shortcuts),
  the device frame (SVG with button hotspots), and the installer (chip id, firmware manifest).
  It also answers `m5emu.boardReady()` (called by `m5:begin_/1`) by casting
  `board:<atom>:<w>:<h>` to the VM.
- `src/vm.ts`: instantiates the AtomVM module, registers stdout/stderr to the console pane,
  loads `m5_emu.avm`, then `atomvmlib.avm`, then the app `.avm` into the VM's filesystem and
  starts `main`.
- `src/m5emu.ts`: the renderer. A 135x240 offscreen framebuffer drawn to a visible canvas at
  3x (configurable). Implements the commands in 4.3 with M5GFX semantics: rotation 0–3 swaps
  width and height and transforms coordinates; text cursor advances and wraps the way
  `print`/`println` do in M5GFX; `set_text_size` scales the 6x8 glyphs; `sleep` blanks and
  `wakeup` restores; `brightness` dims via canvas alpha. Font: the 6x8 "Font0" glyph table from
  LovyanGFX (MIT/BSD-compatible), ported to a data file.
- `src/input.ts`: on-screen buttons A, B and power, keyboard shortcuts (`A`, `B`, `P`), a
  battery slider. Sends `Module.cast("m5_emu_input", ...)`.
- `src/audio.ts`: WebAudio square-wave tone with volume, and raw PCM playback (u8, s8, s16).
- `src/loader.ts`: drag-and-drop, file picker and `?avm=<url>` loading; keeps the last app in
  IndexedDB so a reload restarts it.
- `src/installer.ts`: Web Serial via `esptool-js`. Two buttons: **Install runtime** writes the
  full image at `0x1000` (the image and manifest are mirrored into the Pages site under
  `firmware/`, because GitHub release downloads lack CORS headers and COEP blocks them); **Install app** writes the loaded `.avm` at
  `0x250000`. Progress and the device's serial log go to the console pane. Hidden when the
  browser lacks `navigator.serial`.

The page never modifies the wasm binary; `scripts/fetch-atomvm.sh` downloads it from the AtomVM release matching
`ATOMVM_VERSION`, verifies its sha256, and places it under `web/public/atomvm/` (gitignored, fetched at setup and in CI).
`atomvmlib.avm` is built beside it by `scripts/build-atomvmlib.sh`.

## 6. `firmware/`

One directory per board, `firmware/m5stickc_plus2/` in milestone 1:

- `partitions.csv`: the default AtomVM 0.7 layout for the first 4 MB, plus an
  `apps` data partition filling the remaining flash (about 4.6 MB). Milestone 1 does not use
  `apps`; defining it now means milestone 2 never needs a full erase on users' watches.
- `sdkconfig.m5stickc_plus2`: `esp32` target, 8 MB flash, PSRAM off in milestone 1, custom partition CSV, Elixir
  support on.
- `.github/workflows/firmware.yml`: checks out AtomVM at `ATOMVM_VERSION`, adds `atomvm_m5`
  (pinned commit) under `components/`, builds in `espressif/idf:v5.5.1`, assembles a single
  `.img` with esptool's `merge_bin`, and publishes it as a release asset with a `manifest.json`
  the installer reads. `scripts/firmware.sh` runs the same steps locally in Docker.

Upstream contribution tracked in the plan: add `board_M5StickCPlus2` to `m5:get_board/0` in
`atomvm_m5`; until merged, our firmware build applies a one-line patch.

## 7. `m5_emu_mix/` and the example

`mix m5.emulate` (Elixir package, dev-only dependency): runs `mix atomvm.packbeam`, starts a
local static server for `web/dist` with COOP/COEP headers, opens the browser at
`?avm=http://localhost:<port>/app.avm`, and re-packs on file changes. The page polls
`/__version`, a counter bumped after each successful pack, and reloads the VM when it changes
(no WebSocket). No flashing; `mix atomvm.esp32.flash` already does that.

`examples/clock/`: exatomvm project depending on `atomvm_m5`. Shows the UTC time from
`erlang:system_time` since RTC is out of scope, button A cycles three screens, button B beeps
and toggles the LED, the power button toggles sleep (a press sleeps the display, the next wakes it). Runs identically in the
emulator and on the watch; it is the acceptance test for milestone 1.

## 8. Testing

- Erlang (`rebar3 eunit` on OTP 27, not AtomVM): button state machine against scripted
  press/release timelines, display state transitions, command encoding, API-drift check
  against the pinned `atomvm_m5` export lists. The JS bridge is a behaviour; tests inject a
  recording fake.
- JS (vitest): renderer command sequences compared with golden PNGs for each rotation, text
  wrap, text size and color cases; installer offset and image assembly logic.
- End to end (Playwright, Chromium): load `examples/clock` `.avm` in the real wasm VM, assert
  canvas pixels after boot, click A and assert the screen changed, press B and assert a tone
  event was emitted.
- Device (manual checklist in the plan): install runtime, install app, verify the same
  screens on the watch, measure install time.

## 9. Error handling

- Loading a `.avm` with no start module or for a different AtomVM version shows a message in
  the console pane with the version expected.
- VM crash (worker dies): the page shows the last stderr lines and a restart button; the app
  stays loaded.
- Unsupported `m5_*` calls return `{error, unsupported}` and log once per function to the
  console pane, so authors learn what the emulator lacks without the app dying.
- Installer: handles missing Web Serial, no port chosen, wrong chip (checks the chip id is
  ESP32 before writing), and a watch that fails to enter download mode (shows the "hold power
  button while plugging in" hint).

## 10. Milestones

1. Emulator runs `examples/clock`; `dev` works in `devenv shell`; runtime and app flash from the page;
   the same app runs on the watch. (This spec.)
2. App loader: launcher app in `main.avm`, apps stored in the `apps` partition, runtime
   loading with `atomvm:add_avm_pack_binary/2`, installer writes to free slots, emulator
   models the `apps` partition. (Next spec.)
3. Later: more boards (other M5 devices first, since `atomvm_m5` covers them; non-M5 ESP32
   watches need their own board library), IMU, RTC, battery via I2C emulation, Gleam example,
   hosted gallery of apps.

## 11. Future direction, not planned: native emulation

A later option is to fork AtomVM's emscripten platform and compile `atomvm_m5`'s NIFs against
M5GFX's SDL backend, giving pixel-exact rendering and the real button class. It costs a C and
Emscripten toolchain and several weeks; it changes nothing for apps or the page because the
API boundary is `atomvm_m5` in both cases. Revisit when font or timing drift between emulator
and device becomes a real problem.

## 12. Risks and early checks

| Risk | Check in plan |
|------|---------------|
| `run_script` throughput too low for drawing-heavy loops | Benchmark 1000 `fill_rect` per second in the first emulator task; fall back to a shared binary ring buffer if needed |
| Module shadowing order differs in a future AtomVM | Node smoke test and E2E test assert `m5:get_board/0` returns `stick_cplus2` under the wasm VM |
| Font or text wrapping differs from M5GFX | Golden frames compared against photos of the watch for the example screens |
| `atomvm_m5`, AtomVM wasm and firmware versions drift | `versions.env` holds `ATOMVM_VERSION` and the pinned `atomvm_m5` commit; CI builds all three from them |
| `m5:update/0` busy loop in the browser | Example uses `timer:sleep(10)` like upstream examples; document it |
| GitHub Pages and the service-worker header trick | Smoke test on the deployed URL in CI |

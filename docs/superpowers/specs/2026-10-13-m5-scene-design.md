# m5_scene — avm_scene scenes on m5_display, first board M5StickC Plus 2

Date: 2026-10-13
Status: draft, awaiting review
Branch: `m5-scene` (from `milestone-1`)

## 1. Goal

Let apps describe their screen as scenes and display lists, the way AtomVM's own UI stack does
(`avm_scene` + AtomGL), while still drawing through `atomvm_m5`'s `m5_display` on the
M5StickC Plus 2. Apps written this way run unchanged in the browser emulator and on the watch,
and can move to real AtomGL later by changing one option.

This is the base the milestone 2 launcher will be built on. The launcher itself is not part of
this work and gets its own spec.

Why scenes: portability to boards without M5 libraries, flicker-free redraws of a whole screen,
reasoning in scenes and state instead of imperative drawing, and alignment with upstream AtomVM.

## 2. Decisions and context

- **No AtomGL in the firmware for now.** `m5:begin_/1` calls `M5.begin()`, which always
  initialises the ST7789 over SPI (M5Unified even detects the board by probing the panel), and
  none of `atomvm_m5`'s options turn that off. AtomGL would need the same SPI bus, and skipping
  `m5:begin_` loses buttons, speaker, RTC, power and the GPIO 4 power hold. Instead, `m5_scene`
  implements the display side of `avm_scene` in Erlang on top of `m5_display`.
- **`avm_scene` accepts any display module.** It takes `{display_server, {Module, Display}}` and
  sends each frame as `Module:call(Display, {update, DisplayList})`; input comes from any
  `{input_server, Pid}` that answers `{subscribe_input}` and sends
  `{input_event, Pid, Timestamp, Event}`. Checked against `avm_scene` `aba9249` (2025-11-02),
  published on Hex.
- **Moving to AtomGL later** means AtomGL firmware for the board and
  `display_server: {port, Display}`. Scenes that use only AtomGL's four item types need no change.
- **`m5_display` stays available.** An app draws either through `m5_scene` or directly with
  `m5_display`, not both: both paint the same screen, and `m5_scene` assumes it owns it.
- **Two `atomvm_m5` gaps are closed with an additive patch:** it has no text colour
  (`setTextColor`) and no image push (`pushImage`). See section 5.
- **The emulator needs no AtomGL emulation.** `m5_scene` only calls `m5_display`, which `m5_emu`
  already provides in the browser.

## 3. Components

| Path | What |
|------|------|
| `m5_scene/` | New rebar3 library (Erlang, usable from Elixir, Erlang and Gleam apps). Depends only on `atomvm_m5`'s public modules. |
| `firmware/m5stickc_plus2/patches/0002-display-text-color-push-image.patch` | Adds `m5_display:set_text_color/2` and `m5_display:push_image/5` to `atomvm_m5`. |
| `m5_emu/` | Implements the two new functions on the canvas; the API snapshot is regenerated. |
| `examples/scenes/` | New Elixir example: a menu scene and a detail scene. |
| `docs/` | Item reference and usage notes (section 9). |

`m5_scene` modules:

- `m5_scene`: entry point. `m5_scene:start_link(Opts)` sets the rotation, starts the display and
  input processes and returns `{ok, SceneOpts}` where
  `SceneOpts = [{display_server, {m5_scene_display, DisplayPid}}, {input_server, InputPid}]`, ready
  to pass to `avm_scene`. `Opts`: `rotation` (default 1, landscape), `poll_ms` (default 10),
  `background` (default `16#000000`).
- `m5_scene_display`: gen_server holding the last display list. `call(Pid, {update, List})` is what
  `avm_scene` invokes; it asks the renderer for a draw plan and runs it against `m5_display`.
- `m5_scene_render`: pure functions, no side effects: item validation, bounding boxes, comparison
  of the old and new lists, draw plan (a list of `m5_display` operations), RGBA to RGB565
  conversion.
- `m5_scene_input`: gen_server that polls the buttons and sends input events to subscribers.

## 4. Display list

Coordinates and sizes are integer screen pixels. Colours are 24-bit RGB integers (only the low 24
bits are used). `Bg` is a colour or the atom `transparent`. **The first item in the list is drawn
on top**, as in AtomGL. Values beyond ±32767 are clamped, as in AtomGL.

AtomGL item types (same tuples as upstream):

| Item | Notes |
|------|-------|
| `{rect, X, Y, W, H, Color}` | Filled. `W` or `H` ≤ 0 draws nothing. |
| `{text, X, Y, Font, Fg, Bg, Text}` | `Text` is a string or a UTF-8 binary. `default16px` maps to M5GFX text size 2 (12×16 per character); AtomGL's font is 8×16, so text is wider here. Extension fonts `m5_font1` … `m5_font4` select text sizes 1 to 4 (6×8 per character times the size). |
| `{image, X, Y, Bg, {rgba8888, W, H, Pixels}}` | `Pixels` holds at least `W*H*4` bytes. |
| `{scaled_cropped_image, X, Y, W, H, Bg, SrcX, SrcY, XScale, YScale, [], Image}` | Same validity rules as AtomGL. |

Extension item types (not in AtomGL; real AtomGL skips them with a log line, so scenes that use
them are not portable to AtomGL boards):

| Item | Notes |
|------|-------|
| `{round_rect, X, Y, W, H, Radius, Color}` | Filled. |
| `{circle, CX, CY, R, Color}` | Filled. |
| `{line, X1, Y1, X2, Y2, Color}` | One pixel wide. |

## 5. `atomvm_m5` patch

Patch `0002` adds two NIFs to `atomvm_m5`'s display table, written with the wrapper macros the file
already uses, and their Erlang stubs in `m5_display.erl`. Existing functions are unchanged.

- `m5_display:set_text_color(Fg, Bg) -> ok`: M5GFX `setTextColor(fg, bg)`, colours as 24-bit RGB.
  Passing the same value for `Fg` and `Bg` keeps M5GFX's transparent-background behaviour.
- `m5_display:push_image(X, Y, W, H, Rgb565) -> ok`: M5GFX `pushImage` with a binary of `W*H*2`
  bytes, RGB565 big-endian. A shorter binary raises `badarg`.

The patch is applied by `firmware/build.sh` with the existing patch loop, so the firmware CI builds
it with no script change. It is a candidate for an upstream PR to `atomvm_m5`.

## 6. Rendering

On `{update, List}` the display process:

1. Validates every item. Invalid items (wrong arity or types, unknown command, short image
   binary) are dropped from the plan and logged as
   `invalid display list item N (Cmd/Arity): Reason`, at most 3 lines per update plus a count of the
   rest, matching AtomGL's format. A list that is not a proper list is rejected:
   `{error, invalid_display_list}` is returned and the previous frame stays on screen.
2. Computes each item's bounding box. Text: character count × character width by character height
   for its font.
3. Compares with the previous list. The dirty area is the union of the boxes of items added,
   removed or changed, at their old and new positions.
   - Nothing changed: nothing is drawn.
   - Dirty area over half the screen: full redraw.
   - Otherwise, for each dirty rectangle: set the clip rectangle, fill it with the background
     colour, draw the overlapping items from last to first, clear the clip.
4. Wraps all drawing in `start_write`/`end_write`, then replies `ok`.

Images: RGBA is converted to RGB565 and drawn with `push_image`. With an opaque `Bg`, pixels are
alpha-blended against it before the push. With `transparent`, only pixels with alpha ≥ 128 are
drawn, pushed as horizontal runs. Converted images are cached by their pixel binary, so an icon
that appears in every frame is converted once.

Screen size comes from `m5_display:width/0` and `height/0` after the rotation is set: 240×135 in
landscape, 135×240 in portrait on the StickC Plus 2.

## 7. Input

`m5_scene_input` calls `m5:update()` every `poll_ms`, then reads `m5_btn_a`, `m5_btn_b` and
`m5_btn_pwr` and sends one `{input_event, self(), Ts, Event}` per change to each subscriber
(`Ts` from `erlang:system_time(millisecond)`):

| `atomvm_m5` state | Event |
|-------------------|-------|
| `was_pressed` | `{button, Name, pressed}` |
| `was_released` | `{button, Name, released}` |
| `was_clicked` | `{button, Name, click}`, sent at once |
| `was_double_clicked` | `{button, Name, double_click}`, after the `click` of the first press |
| `was_hold` | `{button, Name, hold}`, once at the hold threshold; no `click` follows |

`Name` is `a`, `b` or `pwr`. `{subscribe_input}` adds the caller; subscribers are monitored and
removed when they exit. The module that reads button state is a start option, so tests use a fake.

`m5_scene_input` owns `m5:update()`: the `was_*` flags reset on every update, so an app that also
calls `m5:update()` loses events. Documented in the usage notes.

## 8. Error handling

- Invalid items and lists: section 6. A bad frame never crashes a scene.
- Text and shapes outside the screen are clipped by M5GFX.
- `m5_scene_display` and `m5_scene_input` are linked to the caller of `m5_scene:start_link/1`. If
  either crashes, the app crashes with it and its supervisor decides; no hidden restarts that could
  leave the screen inconsistent.

## 9. Example and docs

`examples/scenes/` (Elixir, `avm_scene` from Hex, `m5_scene` as a path dependency, `m5_emu_mix`
for `mix m5.emulate`):

- Menu scene: a title, three entries with an icon each, a rounded highlight bar with inverted
  text. A moves the highlight, B opens the entry.
- Detail scene: the entry's name and a line drawing (circle, line); B goes back, A held for the
  hold threshold also goes back.

Docs: a `m5_scene/README.md` with the item reference (AtomGL types and extension types marked),
the `m5_scene` versus `m5_display` rule, the `m5:update()` ownership rule, the
`click`/`double_click` ordering and the font size difference from AtomGL. `docs/overview` gets a
short section pointing to it, and the roadmap records "AtomGL firmware" as a later item.

## 10. Testing

- `m5_scene` eunit (host BEAM), added to `scripts/test.sh`:
  - `m5_scene_render`: bounding boxes for every type; comparison (no change, one item moved,
    items added and removed, reordered list); the full-redraw threshold; back-to-front order in a
    dirty rectangle; invalid items and their log lines; RGBA to RGB565 with blending and
    `transparent`; the image cache.
  - `m5_scene_input` with a fake button module: each state gives the right event; subscribe and
    removal of dead subscribers.
  - `m5_scene_display` against a recording fake `m5_display`: a frame becomes the expected call
    sequence inside `start_write`/`end_write`.
- `m5_emu`: tests for `set_text_color/2` and `push_image/5`; `scripts/gen-atomvm-m5-api.sh` runs on
  the patched `atomvm_m5` so the API-parity test covers the new functions.
- End to end: `examples/scenes` is built into the committed fixture `web/e2e/fixtures/scenes.avm`
  (by `scripts/build-example.sh`), and `web/e2e/scenes.spec.ts` presses A and B and checks canvas
  pixels: the highlight moves, the detail scene opens and closes, inverted text and the icon draw.
- Device: the firmware CI builds the image with patch `0002`. `docs/device-checklist.md` gets a
  scenes section: flash the runtime and `scenes.avm`, colours and icon correct, no visible flicker
  moving the highlight, buttons on battery. Flashing and the serial log can be driven from the
  development machine; looking at the screen and pressing buttons needs a person.
- Performance: the e2e test and the device checklist record the time from button press to redraw
  for a highlight move. Target on the watch: under 50 ms.

## 11. Out of scope

- AtomGL in the firmware, and the `display` port.
- ufont and fonts other than M5GFX's built-in font.
- Outline shapes, text alignment items, sprites.
- The launcher, app storage and loading (milestone 2 spec).
- Converting `examples/clock` to scenes.

## 12. Risks

| Risk | Check |
|------|-------|
| Redrawing through the emulator's bridge is too slow for smooth highlight moves | The e2e timing; if far above the device, fall back to full-frame batching in the bridge |
| `push_image` RGB565 byte order differs between M5GFX and the emulator | A two-colour test image checked in the e2e test and on the device |
| `avm_scene` from Hex fails to build or run under AtomVM 0.7.0-beta.0 | First task of the plan: a minimal scene that pushes one `rect` in the emulator |
| Text bounding boxes differ from what M5GFX draws (UTF-8, wide glyphs) | Bounding boxes use M5GFX's own `font_width`/`font_height`; non-ASCII text gets a test |

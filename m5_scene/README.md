# m5_scene

`m5_scene` runs [`avm_scene`](https://github.com/atomvm/avm_scene) scenes on the M5StickC Plus 2
through `atomvm_m5`'s `m5_display`. It provides the two processes `avm_scene` needs: a display
server, which diffs each display list against the previous one and redraws only the changed areas,
and an input server, which polls the buttons. The same app runs in the browser emulator and on the
watch with this repository's firmware (`firmware/m5stickc_plus2/README.md`): it needs patch `0002`
for two display functions, and the PSRAM the firmware enables for the display server's heap.

```elixir
:m5.begin_([])
{:ok, scene_opts} = :m5_scene.start_link(rotation: 1, background: 0x000000)
{:ok, _} = :avm_scene.start_link(MyScene, [], scene_opts)
```

| Option | Default | Meaning |
| --- | --- | --- |
| `rotation` | `1` | `m5_display` rotation; 1 is landscape, 240×135 |
| `poll_ms` | `10` | Button poll period in milliseconds |
| `background` | `0x000000` | Colour behind every item |

`examples/scenes` is a complete app: a menu scene and a detail scene.

## Rules

- An app draws through `m5_scene` or directly with `m5_display`, never both. Both paint the same
  screen, and `m5_scene` only redraws what its display list changed, so direct drawing is
  overwritten or left behind unpredictably.
- `m5_scene` owns `m5:update/0`. The `was_*` button flags reset on every update, so an app that
  also calls it loses button events.
- The display and input servers are linked to the process that calls `start_link/1`.

## Display list

The first item in the list is drawn on top, as in AtomGL. Coordinates and sizes are integer
pixels. Colours are 24-bit RGB integers (only the low 24 bits are used). `Bg` is a colour or the
atom `transparent`. `rect` and `text` values beyond ±32767 are clamped; image and shape values
outside ±32767 make the item invalid.

| Item | Notes |
| --- | --- |
| `{rect, X, Y, W, H, Color}` | Filled. `W` or `H` ≤ 0 draws nothing. |
| `{text, X, Y, Font, Fg, Bg, Text}` | `Text` is a string or a UTF-8 binary. An opaque `Bg` fills the text's box first. |
| `{image, X, Y, Bg, {rgba8888, W, H, Pixels}}` | `Pixels` holds at least `W*H*4` bytes. With `transparent`, pixels with alpha ≥ 128 are drawn; with a colour, pixels are blended against it. |
| `{scaled_cropped_image, X, Y, W, H, Bg, SrcX, SrcY, XScale, YScale, Opts, Image}` | Same rules as AtomGL; `Opts` may hold `flip_x` and `flip_y`. |
| `{rounded_rect, X, Y, W, H, Radius, Color}` | Filled. Radius clamped to `(min(W, H) - 1) div 2`. |
| `{circle, CX, CY, R, Color}` | Filled, `R > 0`. |
| `{ellipse, CX, CY, RX, RY, Color}` | Filled, `RX, RY > 0`. |
| `{line, X1, Y1, X2, Y2, Thickness, Color}` | `Thickness >= 1`. |

Differences from AtomGL:

- Fonts: `default16px` is M5GFX text size 2, 12×16 per character (AtomGL's is 8×16, so text is
  wider here). `m5_font1` … `m5_font4` select text sizes 1 to 4 (6×8 per character times the
  size); they are `m5_scene` only, and AtomGL logs `unsupported font` for them and falls back.
  Any other font atom is drawn as `default16px` and logged as `unsupported font`.
- `arc` and `polygon` are not supported: they are logged as `unsupported command` and skipped.
- Lines thicker than 1 are approximated with two triangles, plus round caps from thickness 3.
  Shape edges can differ by a pixel from AtomGL's.

Images are converted to RGB565 one row at a time, and the result stays cached while the image is
in the display list: W×H×2 bytes per image (64 KB for a full 240×135 screen). Images that leave the
list stay cached too, most recently shown first, up to 32 KB, so the frames of an animation are
converted once. Allocations from 16 KB up go to the watch's 2 MB PSRAM, which is slower than internal
RAM.

Invalid items are skipped and logged (at most three lines per frame, then a count). A display list
that is not a proper list is rejected with `{error, invalid_display_list}` and the previous frame
stays on screen.

## Input events

Each subscriber gets `{input_event, InputPid, Ts, Event}`, with `Ts` from
`erlang:system_time(millisecond)` and `Name` one of `a`, `b`, `pwr`:

| `atomvm_m5` state | Event |
| --- | --- |
| `was_pressed` | `{button, Name, pressed}` |
| `was_hold` | `{button, Name, hold}`, once at the hold threshold |
| `was_released` | `{button, Name, released}` |
| `was_clicked` | `{button, Name, click}` |
| `was_double_clicked` | `{button, Name, double_click}` |

Each poll reads a button's states only for 2 seconds after its last press or release (and for
2 seconds after start), which covers the hold threshold and the click decisions; idle buttons cost
one call each. Within one poll, events come in the order of the table. `click` is sent at the release of a short
press; `double_click` comes after the second press's `click`; a hold sends `hold` and no `click`.

## Moving to AtomGL later

With AtomGL in the firmware, an app opens AtomGL's display port and passes
`display_server: {port, Display}` to `avm_scene` instead of `m5_scene`'s options. Scenes that use
only AtomGL items and fonts are unchanged; the input server is still needed for the buttons.

## Performance

In the emulator, a highlight move in `examples/scenes` is on screen about 210 ms after the start
of the end-to-end test's click, which itself holds the button for 150 ms; the scene reacts on
press. The device target is under 50 ms from press to redraw (to be measured, see
`docs/device-checklist.md`).

## Tests

`rebar3 eunit` runs everything on the host BEAM with fake display and button modules, including
an integration test against the real `avm_scene` from Hex. `web/e2e/scenes.spec.ts` runs
`examples/scenes` in the AtomVM wasm emulator.

# Device checklist (M5StickC Plus 2, manual)

Needs the watch on USB and a Chrome or Edge browser. Record results in
`firmware/m5stickc_plus2/README.md` (they are marked TBD there) and tick the boxes here.

## Terminal flash (before trusting the web installer)

- [x] Flash the runtime and the smoke app with `esptool` (commands in `firmware/m5stickc_plus2/README.md`, at 115200 baud).
- [x] Serial (`screen /dev/cu.usbserial-* 115200`) shows the AtomVM banner.
- [x] Serial shows `SMOKE board stick_cplus2 135x240` (proves the `get_board` patch).
- The smoke app then stops at `stub_pack_probe.beam`: its remaining checks (screen, buttons,
  throughput) are emulator-only. Throughput on the device is not measured.

## Clock example

- [ ] `cd examples/clock && mix atomvm.esp32.flash --port /dev/cu.usbserial-*` succeeds
      (the 2026-10-13 run flashed `clock.avm` at 0x250000 with esptool instead).
- [x] Button A cycles three screens: clock (UTC time ticking), buttons, about (`board: stick_cplus2`).
- [x] Button B beeps and toggles the red LED.
- [x] Each Power press toggles the display between sleep (blank) and wake (screen returns).
- [x] Keeps running on battery with USB unplugged.
- [x] Text and fonts look right (compare against the emulator by eye; known to differ slightly).

## Scenes example (`m5_scene`, firmware with patch 0002)

- [x] Flash the runtime built with patch `0002` and `scenes.avm` (`esptool ... write-flash 0x250000 scenes.avm`, 115200 baud).
- [x] Menu shows the title, three entries with red, green and blue discs, a white rounded highlight with black text.
- [x] A moves the highlight with no visible flicker; B opens the detail (cyan circle, yellow line); B and hold A go back.
- [x] Colours match the emulator (RGB565 byte order: the red disc is red, not blue).
- [x] Highlight move feels instant (target under 50 ms; serial timing optional).
- [x] Works on battery.
- Power does nothing in this example: it binds only A and B (verified 2026-10-15, firmware from CI run 38535990143).

- [ ] Re-check the menu and detail screens on the firmware with PSRAM (CI run 38707497018).

## Firmware and `m5_scene` performance (measured 2026-10-15)

`examples/nyan` (a sprite, a rainbow trail of up to 60 rectangles and twinkling stars, a 50 ms tick)
on the watch, with frame timing printed over serial. Runs differ in length, so frames per second.

| Firmware | `m5_scene` | Frames per second | Notes |
| --- | --- | --- | --- |
| IDF debug build (-Og), 160 MHz, flash DIO 40 MHz | before the image cache kept dropped images | under 1 | each sprite frame converted again every other frame, 5 s each |
| release optimization, 160 MHz, DIO 40 MHz | image cache, `fibonacci` heap | 1.2 | 49 frames in 40 s |
| as above, 240 MHz | same | 1.4 | CPU clock alone barely helps: code runs from flash |
| 240 MHz, flash QIO 80 MHz | image cache as one binary, default heap | 1.5 | 110 frames in 75 s; `fibonacci` aborted without PSRAM |
| same | fewer allocations per frame, input window | 3.7 | 281 frames in 75 s |
| same, with PSRAM | same | 3.3 | 245 frames in 75 s |
| same, with PSRAM | display server with `fibonacci` heap | 5.3 | 399 frames in 75 s; 1316 in 4 minutes, no abort |
| PSRAM at 80 MHz | same | 5.4 | 408 frames in 75 s, within noise, not kept |

## Web installer

- [ ] Open `https://tomashco.github.io/atomvm_watch/?avm=./fixtures/clock.avm` (the plain URL starts empty), the emulator runs the clock.
- [ ] Click **Connect**, then **Install runtime** (needs a mirrored firmware release on the site) and,
      on the same serial connection, **Install app**; progress and
      the serial log appear in the console pane and the watch boots the clock.
- [x] **Connect** then **Install app** alone (from `dev`, 2026-10-13: under five seconds) (runtime already present) finishes in under five seconds.
- [ ] Unplugging mid-install shows an error in the console pane and leaves the page usable.

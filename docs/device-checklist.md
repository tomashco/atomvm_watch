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

- [ ] Flash the runtime built with patch `0002` and `scenes.avm` (`esptool ... write-flash 0x250000 scenes.avm`, 115200 baud).
- [ ] Menu shows the title, three entries with red, green and blue discs, a white rounded highlight with black text.
- [ ] A moves the highlight with no visible flicker; B opens the detail (cyan circle, yellow line); B and hold A go back.
- [ ] Colours match the emulator (RGB565 byte order: the red disc is red, not blue).
- [ ] Highlight move feels instant (target under 50 ms; serial timing optional).
- [ ] Works on battery.

## Web installer

- [ ] Open `https://tomashco.github.io/atomvm_watch/?avm=./fixtures/clock.avm` (the plain URL starts empty), the emulator runs the clock.
- [ ] Click **Connect**, then **Install runtime** (needs a mirrored firmware release on the site) and,
      on the same serial connection, **Install app**; progress and
      the serial log appear in the console pane and the watch boots the clock.
- [x] **Connect** then **Install app** alone (from `dev`, 2026-10-13: under five seconds) (runtime already present) finishes in under five seconds.
- [ ] Unplugging mid-install shows an error in the console pane and leaves the page usable.

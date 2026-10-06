# Device checklist (M5StickC Plus 2, manual)

Needs the watch on USB and a Chrome or Edge browser. Record results in
`firmware/m5stickc_plus2/README.md` (they are marked TBD there) and tick the boxes here.

## Terminal flash (before trusting the web installer)

- [ ] Flash the runtime and the smoke app with `esptool` (commands in `firmware/m5stickc_plus2/README.md`).
- [ ] Serial (`screen /dev/cu.usbserial-* 115200`) shows the AtomVM banner.
- [ ] Serial shows `SMOKE board stick_cplus2 135x240` (proves the `get_board` patch).
- [ ] Screen shows a red rectangle and "hello"; `SMOKE a_pressed` is `false`.
- [ ] Throughput numbers recorded: `fill_rect_1000_ms`, `batched_1000_ms`.

## Clock example

- [ ] `cd examples/clock && mix atomvm.esp32.flash --port /dev/cu.usbserial-*` succeeds.
- [ ] Button A cycles three screens: clock (UTC time ticking), buttons, about (`board: stick_cplus2`).
- [ ] Button B beeps and toggles the red LED.
- [ ] Each Power press toggles the display between sleep (blank) and wake (screen returns).
- [ ] Text and fonts look right (compare against the emulator by eye; known to differ slightly).

## Web installer

- [ ] Open `https://tomashco.github.io/atomvm_watch/`, the emulator runs the clock.
- [ ] Click **Install runtime** then, on the same serial connection, **Install app**; progress and
      the serial log appear in the console pane and the watch boots the clock.
- [ ] **Install app** alone (runtime already present) finishes in under five seconds. Time: ____ s.
- [ ] Unplugging mid-install shows an error in the console pane and leaves the page usable.

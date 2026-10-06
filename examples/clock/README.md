# clock

Reference app for atomvm_watch: a clock face, button-driven screens, a beep and the LED. It uses
only `m5`, `m5_display`, `m5_btn_a`, `m5_btn_b`, `m5_btn_pwr`, `m5_speaker` and `gpio`, so the same
`clock.avm` runs in the browser emulator and on the M5StickC Plus 2.

| Button | Action |
| --- | --- |
| A | next screen: clock, buttons, about |
| B | beep (1800 Hz, 80 ms) and toggle the LED (GPIO 19) |
| Power | display sleeps while held, wakes on release |

```bash
mix deps.get
mix atomvm.packbeam                                      # writes clock.avm
mix atomvm.esp32.flash --port /dev/cu.usbserial-*        # flashes clock.avm at 0x250000
```

`mix atomvm.packbeam` warns that the `m5_btn_*` functions are not available on AtomVM: they come
from the `atomvm_m5` ESP-IDF component, not the AtomVM API list. That is a warning, not an error.

To try it in the emulator, open the web page and drop `clock.avm` on it. `scripts/build-example.sh`
rebuilds it and refreshes the end-to-end fixture `web/e2e/fixtures/clock.avm`.

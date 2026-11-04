# gleam_hello

The smallest Gleam app for the watch: a counter drawn directly with `atomvm_m5`'s `m5_display`.
It runs in the browser emulator and on the M5StickC Plus 2. It uses `m5_display:set_text_color/2`,
so the watch needs firmware v0.2.0 or later (the one **Install runtime** installs from the site).

| Button | Action |
| --- | --- |
| A | add one |
| B | beep and reset to zero |

```bash
scripts/build-gleam-example.sh gleam_hello      # from the repo root, inside the devenv shell
```

That writes `examples/gleam_hello/gleam_hello.avm`. Drop it on the emulator page, then use
**Install to device** to put it on the watch, or flash it from a terminal:

```bash
esptool --chip esp32 --port /dev/cu.usbserial-* --baud 115200 write-flash 0x250000 examples/gleam_hello/gleam_hello.avm
```

## How it works

- `src/gleam_hello/m5.gleam` declares the `atomvm_m5` functions the app calls with
  `@external(erlang, ...)`. Gleam inlines those calls, so the app module calls `m5_display` directly.
- `pub fn start()` is the entry point: AtomVM calls the start module's `start/0`.
- AtomVM has only part of OTP, and so only part of `gleam_stdlib` works on it. `gleam/int`'s
  `to_string` does. If a function you use calls something AtomVM lacks, the app stops with an
  `undef` error, in the emulator as on the watch.
- `gleam build` can't fetch `atomvm_m5`: Gleam's git and path dependencies must be Gleam projects.
  `scripts/build-gleam-example.sh` builds it, `avm_scene` and `m5_scene` with rebar3
  (`scripts/gleam_libs`), then packs everything the start module reaches into the `.avm`.

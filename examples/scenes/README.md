# scenes

Example for `m5_scene`: two `avm_scene` screens drawn through `atomvm_m5`'s `m5_display`, the same
`scenes.avm` in the browser emulator and on the M5StickC Plus 2 (with the firmware that has patch
`0002`; see `firmware/m5stickc_plus2/README.md`).

| Screen | Button | Action |
| --- | --- | --- |
| menu | A | move the highlight |
| menu | B | open the entry |
| detail | B, or hold A | back to the menu |

```bash
mix deps.get
mix atomvm.packbeam                                      # writes scenes.avm
mix atomvm.esp32.flash --port /dev/cu.usbserial-*        # flashes scenes.avm at 0x250000
mix m5.emulate                                           # emulator dev loop
```

See `m5_scene/README.md` for the display list items and the rules (an app uses `m5_scene` or
`m5_display`, not both; `m5_scene` owns `m5:update/0`). `scripts/build-example.sh` rebuilds the
end-to-end fixture `web/e2e/fixtures/scenes.avm`.

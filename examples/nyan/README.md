# nyan

Animation example and performance benchmark for `m5_scene`: a pixel-art cat flies across the screen
with a rainbow trail and twinkling stars, one `avm_scene` frame every 50 ms. It uses scaled sprites,
cached images and many small rects every frame, so it shows what the
firmware and `m5_scene` can sustain. The frame rates measured on the watch are in
`docs/device-checklist.md` (5.3 fps on the PSRAM firmware).

Needs the firmware with patch `0002` (see `firmware/m5stickc_plus2/README.md`), and the PSRAM firmware
for the `fibonacci` heap growth of `m5_scene`'s display server.

| Button | Action |
| --- | --- |
| A | pause and resume |
| B | change speed (2, 4, 6 px per tick) |

```bash
mix deps.get
mix atomvm.packbeam                                      # writes nyan.avm
mix atomvm.esp32.flash --port /dev/cu.usbserial-*        # flashes nyan.avm at 0x250000
mix m5.emulate                                           # emulator dev loop
```

The example itself does not print frame timing.

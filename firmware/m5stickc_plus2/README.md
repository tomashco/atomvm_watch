# M5StickC Plus 2 firmware

AtomVM (`ATOMVM_VERSION` in `versions.env`) plus the `atomvm_m5` ESP-IDF component
(`ATOMVM_M5_COMMIT`), with an 8 MB partition table.

| File | Purpose |
| --- | --- |
| `partitions.csv` | 8 MB table. `boot.avm` at 0x1D0000, `main.avm` at 0x250000 (the installer's `appOffset`). Checked by `firmware/check_partitions.py`. |
| `sdkconfig.m5stickc_plus2` | sdkconfig overrides: 8 MB flash, custom table. PSRAM stays off. |
| `patches/0001-get_board-stick_cplus2.patch` | Makes `m5:get_board/0` return `stick_cplus2` on this board. |
| `manifest.template.json` | Template for the web installer's `FirmwareManifest`. Image at 0x1000. |

Upstream PR for the patch: not opened yet (open it against `pguyot/atomvm_m5` and put the URL here).

## Build

CI: `.github/workflows/firmware.yml` (PRs touching `firmware/**`, manual dispatch, and tags
`firmware-m5stickc_plus2-v<semver>`; a tag publishes the release assets). The first run takes
20 to 40 minutes.

Local (needs Docker): `devenv shell -- firmware`, output in `firmware/out/`.

Release assets: `AtomVM-m5stickc_plus2-<semver>.img`, `manifest-m5stickc_plus2.json`, `.sha256` files.
Tag firmware releases as full releases: `releases/latest` ignores prereleases.

## Flash from the terminal (to check before trusting the web installer)

```bash
esptool --chip esp32 --port /dev/cu.usbserial-* --baud 921600 write-flash 0x1000 firmware/out/AtomVM-m5stickc_plus2-dev.img
esptool --chip esp32 --port /dev/cu.usbserial-* write-flash 0x250000 m5_emu/test/smoke_app/_build/default/lib/smoke_app.avm
screen /dev/cu.usbserial-* 115200
```

Expected: AtomVM banner, then `SMOKE board stick_cplus2 135x240` (proves the patch), a red
rectangle and "hello" on screen. `SMOKE a_pressed` is `false` on the device. If the display stays
black, check `AVM_M5_DISPLAY_ENABLE=y` in `idf.py menuconfig` and the M5GFX autodetect log
(`[Autodetect] M5StickCPlus2`).

Throughput on real hardware (fill in after the first device run): `fill_rect_1000_ms` TBD,
`batched_1000_ms` TBD.

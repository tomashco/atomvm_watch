# M5StickC Plus 2 firmware

AtomVM (`ATOMVM_VERSION` in `versions.env`) plus the `atomvm_m5` ESP-IDF component
(`ATOMVM_M5_COMMIT`), with an 8 MB partition table.

| File | Purpose |
| --- | --- |
| `partitions.csv` | 8 MB table. `boot.avm` at 0x1D0000, `main.avm` at 0x250000 (the installer's `appOffset`). Checked by `firmware/check_partitions.py`. |
| `sdkconfig.m5stickc_plus2` | sdkconfig overrides: 8 MB flash, custom table, I2C legacy conflict check skipped (see below). PSRAM stays off. |
| `patches/0001-get_board-stick_cplus2.patch` | Makes `m5:get_board/0` return `stick_cplus2` on this board. |
| `patches/0002-display-text-color-push-image.patch` | Adds `m5_display:set_text_color/2` and `m5_display:push_image/5` (used by `m5_scene`). |
| `manifest.template.json` | Template for the web installer's `FirmwareManifest`. Image at 0x1000. |

Two I2C drivers are linked: AtomVM's `i2c` (legacy IDF driver) and M5GFX/M5Unified (the new
`i2c_master` driver). ESP-IDF 5.5 aborts at boot when both are present
(`i2c: CONFLICT! driver_ng is not allowed to be used with this old driver`), so the sdkconfig sets
`CONFIG_I2C_SKIP_LEGACY_CONFLICT_CHECK=y`. They must not drive the same port: do not open Erlang
`i2c` on the internal bus (RTC, power chip) that M5Unified owns.

Upstream PRs for the patches: not opened yet (open `0001` and `0002` against `pguyot/atomvm_m5`
and put the URLs here). `0002` is the better upstream candidate: it adds general display functions.

The full manual device procedure with expected observations is `docs/device-checklist.md`.
The Pages workflow mirrors the latest release's manifest and image into the site (`firmware/`),
because release downloads lack CORS headers under COEP. The mirror refreshes only on the next push
to `main` or a manual `workflow_dispatch` of the `pages` workflow, so after publishing a new
firmware release, run `pages` by hand.

## Build

CI: `.github/workflows/firmware.yml` (PRs touching `firmware/**`, manual dispatch, and tags
`firmware-m5stickc_plus2-v<semver>`; a tag publishes the release assets). The first run takes
20 to 40 minutes.

Local (needs Docker): `devenv shell -- firmware`, output in `firmware/out/`.

Release assets: `AtomVM-m5stickc_plus2-<semver>.img`, `manifest-m5stickc_plus2.json`, `.sha256` files.
Tag firmware releases as full releases: `releases/latest` ignores prereleases.

## Flash from the terminal (to check before trusting the web installer)

```bash
esptool --chip esp32 --port /dev/cu.usbserial-* --baud 115200 write-flash 0x1000 firmware/out/AtomVM-m5stickc_plus2-dev.img
esptool --chip esp32 --port /dev/cu.usbserial-* --baud 115200 write-flash 0x250000 m5_emu/test/smoke_app/_build/default/lib/smoke_app.avm
screen /dev/cu.usbserial-* 115200
```

Use 115200 baud: on the watch's CH9102 adapter 921600 and 460800 failed intermittently ("Unable
to verify flash chip connection", "Failed to enter compressed flash mode").

Expected: AtomVM banner, then `SMOKE board stick_cplus2 135x240` (proves the patch). The smoke app
then stops with `Failed load module: stub_pack_probe.beam`: its later checks are emulator-only, so
on the device it proves only the boot and the `get_board` patch. If the display stays
black, check `AVM_M5_DISPLAY_ENABLE=y` in `idf.py menuconfig` and the M5GFX autodetect log
(`[Autodetect] M5StickCPlus2`).

Throughput on real hardware: not measured (the smoke app stops before its timing checks on the
device).

## Device check with the clock example (manual, needs the watch on USB)

1. `cd examples/clock && mix atomvm.esp32.flash --port /dev/cu.usbserial-*`.
2. Confirm the three screens cycle on A (clock, buttons, about with `board: stick_cplus2`), B
   beeps and toggles the red LED, and each Power press toggles
   the display between sleep and wake.
3. Install the same `clock.avm` through the web page ("Install app") and time it (target: under
   five seconds).

Results (2026-10-13, CI firmware from `8c1fced`, clock flashed with esptool): screens pass,
beep/LED pass, sleep/wake pass, runs on battery. Web "Install app" from `dev` works and the
watch restarts into the clock in under five seconds.

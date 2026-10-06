# 04 — Hardware

AtomVM ports exist for ESP32, STM32, RP2040, generic Unix and Emscripten/WASM. Watch-shaped
boards supported by `atomvm_m5` are all ESP32, so that is the target family.

## First board: M5StickC Plus 2

https://docs.m5stack.com/en/core/StickC-Plus2

| | |
|--|--|
| SoC | ESP32-PICO-V3-02 (8 MB flash, 2 MB PSRAM, PSRAM unused in milestone 1) |
| Display | 1.14" ST7789V2, 135×240, colour |
| Input | 3 buttons: A (front), B (side), Power. In M5Unified these are `btn_a`, `btn_b`, `btn_pwr`; there is no button C |
| Sensors | MPU6886 6-axis IMU, mic, RTC (BM8563), battery ADC |
| Other | buzzer, red LED + IR (shared pin), 200 mAh battery, Grove port, Wi‑Fi + BLE |
| AtomVM support | [`pguyot/atomvm_m5`](https://github.com/pguyot/atomvm_m5) (M5Unified/M5GFX bindings) |
| `m5` board atom | `stick_cplus2` |

Pins (M5Unified handles them all; listed for reference):

| Function | Pins |
|----------|------|
| Display ST7789V2 | MOSI 15, CLK 13, DC 14, RST 12, CS 5, BL 27 |
| Buttons | A 37, B 39, Power 35 |
| HOLD (power latch) | 4 |
| Red LED / IR | 19 |
| Buzzer | 2 |
| I²C | SDA 21, SCL 22 |
| Battery ADC | 38 |

Board notes:

- The display goes through `atomvm_m5` (M5GFX), which autodetects the Plus 2 by chip package.
- `atomvm_m5`'s `m5:get_board/0` lacks a Plus 2 case. Our firmware build applies a one-line patch
  returning `stick_cplus2` until the change is merged upstream.
- Milestone 1 uses display, buttons, speaker, LED and battery level. IMU, RTC, HOLD, mic and IR
  come later.
- Download mode: if the installer can't connect, hold the power button while plugging in USB.

## Next boards

Other M5 devices come first, because `atomvm_m5` already supports them and adding one is a new
board profile and firmware directory:

| Board | Display | Input | Why |
|-------|---------|-------|-----|
| M5Stack Core2 | 320×240 ILI9342, touch | touch + 3 virtual buttons | Bigger screen; touch exercises the input side |
| Other M5 sticks / watches | various | buttons | Mostly a data change |

ESP32 watches that aren't M5 (LilyGO T‑Watch S3, Watchy with its e‑paper display) would need a
board library other than `atomvm_m5`. That is out of scope and not designed for yet.

## Board profile

`boards/m5stickc_plus2/board.json`, validated against `boards/schema.json`:

```json
{
  "id": "m5stickc_plus2",
  "name": "M5StickC Plus 2",
  "boardAtom": "stick_cplus2",
  "screen": { "width": 135, "height": 240, "scale": 1.5, "x": 20, "y": 40 },
  "buttons": [
    { "id": "a",   "label": "A",     "key": "a", "x": 87,  "y": 305 },
    { "id": "b",   "label": "B",     "key": "b", "x": 171, "y": 140 },
    { "id": "pwr", "label": "Power", "key": "p", "x": 4, "y": 140 }
  ],
  "peripherals": { "speaker": true, "led": true, "battery": true },
  "chip": "ESP32",
  "firmwareManifest": "firmware/manifest-m5stickc_plus2.json",
  "appOffset": 2424832,
  "deviceImage": "device.svg"
}
```

`appOffset` is `0x250000`. The emulator uses the screen, buttons and peripherals; the installer
uses the chip, the firmware manifest and the app offset.

# 02 — Architecture

## Pipeline

```
app source ──(mix / rebar3 / gleam + packbeam)──▶ app.avm ──▶ web page ──┬─▶ emulator (AtomVM wasm, in the tab)
                                                                         └─▶ watch (Web Serial, written at 0x250000)
```

## Deliverables

One repository, four parts:

| Path | What |
|------|------|
| `boards/<id>/board.json` | Board profile: screen size, buttons (with keyboard shortcut and position on the device image), peripherals, `m5` board atom, chip, firmware manifest URL, app offset |
| `m5_emu/` | Erlang library with the exact module names and arities of `atomvm_m5`, implemented for AtomVM's `emscripten` platform. Packed as `m5_emu.avm` |
| `web/` | Static page (Vite + TypeScript): the wasm VM, the display renderer, device controls, the Web Serial installer |
| `firmware/<board>/` | Partition table, sdkconfig and CI workflow that build the ESP32 runtime image (AtomVM + `atomvm_m5`) |

Plus `m5_emu_mix/` (`mix m5.emulate`) and `examples/clock/` (the reference Elixir app and the
milestone 1 acceptance test).

## The app API is `atomvm_m5`

An app compiles against `atomvm_m5`'s stub modules:

- **On the watch**, the stubs are replaced by `atomvm_m5`'s NIFs (M5Unified 0.2.10, M5GFX 0.2.17).
- **In the browser**, `m5_emu.avm` is loaded first, then `atomvmlib.avm` (built from AtomVM source,
  since the wasm release has no stdlib), then the app's `.avm`. AtomVM resolves a module
  from the first pack that contains it, so `m5_emu` shadows the stubs.

Board-specific values (screen size, board atom, which buttons exist) come from the board profile
at `m5:begin_/1` time; `m5_emu` has no board constants. The second M5 board is a data change.

Functions `m5_emu` doesn't implement return `{error, unsupported}` (never `undef`), and a test
fails if our export list drifts from the pinned `atomvm_m5` revision.

## Browser data flow

```
app .avm ──────┐
atomvmlib.avm ─┤
m5_emu.avm ────┴─> AtomVM-web.wasm (worker thread)
                 │  emscripten:run_script("m5emu.exec([...])")   drawing, tone, led
                 ▼
            web/src/m5emu.ts (main thread) ──> <canvas>, WebAudio, DOM
                 ▲
                 │  Module.cast("m5_emu_input", "a:down")        buttons, battery
            on-screen buttons / keyboard
```

- Drawing calls become commands named after M5GFX's (`fill_rect`, `draw_string`, `print`, …),
  batched between `start_write`/`end_write` and sent to JS as one JSON array. The page draws
  them into a 135×240 framebuffer. Nothing pushes pixels one by one from BEAM code.
- Buttons are a pure Erlang port of M5Unified's `Button_Class` (debounce, hold, click counting,
  `was_*` edge flags), stepped by `m5:update/0`.
- The wasm VM has no ports, so all emulation is plain processes and JS calls.
- The page needs SharedArrayBuffer, hence COOP/COEP headers: set by the dev server, and by
  `coi-serviceworker` on GitHub Pages.

## On the watch

Flash layout (8 MB, ESP32):

| Offset | Size | Content |
|--------|------|---------|
| `0x1000` | | bootloader (start of the runtime image) |
| `0x8000` | | partition table |
| `0x10000` | `0x1C0000` | AtomVM + `atomvm_m5` |
| `0x1D0000` | `0x80000` | `boot.avm` (AtomVM's Erlang/Elixir libraries) |
| `0x250000` | `0x100000` | `main.avm`: the app (milestone 1), the launcher (milestone 2) |
| `0x350000` | `0x4B0000` | `apps`: unused in milestone 1, defined now so milestone 2 needs no full erase |

The installer has two buttons:

- **Install runtime** writes the merged image at `0x1000`. Done once per watch, or on upgrade.
- **Install app** writes the `.avm` at `0x250000`, which takes about a second.

## Milestone 2: on-device loader

A launcher in `main.avm` lists, starts and receives apps stored in the `apps` partition, loading
them at runtime with `atomvm:add_avm_pack_binary/2` (writing with `esp:partition_erase_range/3`
and `esp:partition_write/3`). The installer writes to free slots without reflashing other apps,
and the emulator models the `apps` partition. Specified separately.

## Versions

A single `ATOMVM_VERSION` in `versions.env` (`v0.7.0-beta.0`) pins the wasm VM, `atomvmlib.avm`,
the firmware and the `atomvm` hex package. `atomvm_m5` is pinned to one commit in the same file. CI builds everything from those.

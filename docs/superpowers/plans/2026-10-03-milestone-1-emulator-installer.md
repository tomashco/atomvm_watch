# Milestone 1: Emulator + Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run an `atomvm_m5` app for the M5StickC Plus 2 in the browser on AtomVM's wasm build, and flash the runtime and the app to the watch from the same page.

**Architecture:** An Erlang library `m5_emu` reimplements the `atomvm_m5` module surface for AtomVM's `emscripten` platform and forwards drawing, sound and LED commands to JavaScript as JSON arrays through `emscripten:run_script/2`; JavaScript sends button and battery events back with `Module.cast`. A Vite page hosts the VM, a framebuffer renderer, device controls and an esptool-js installer, all configured from `boards/<id>/board.json`. A GitHub Actions workflow builds the ESP32 runtime image (AtomVM + `atomvm_m5`) with an 8 MB partition table.

**Tech Stack:** Erlang/OTP 27 + rebar3 + `atomvm_rebar3_plugin` (library `.avm`), AtomVM v0.7.0-beta.0 wasm (web + node builds), Vite + TypeScript + vitest + Playwright, `esptool-js` 0.7, `coi-serviceworker`, Elixir 1.18 + `exatomvm` (example app and mix task), ESP-IDF 5.5.1 in Docker.

**Spec:** `docs/superpowers/specs/2026-10-03-atomvm-watch-design.md`

## Global Constraints

- AtomVM version is `v0.7.0-beta.0` everywhere (wasm web, wasm node, firmware, `atomvm` hex package). Single source: `ATOMVM_VERSION` in `mise.toml`.
- `atomvm_m5` is pinned to commit `968508c77c90af5a0109bcd7f0e28a5fa8624c02` (M5Unified 0.2.10, M5GFX 0.2.17).
- `m5_emu` is Erlang only, OTP 27 syntax, compiled with `debug_info`; every public module name and arity matches `atomvm_m5`.
- `m5_emu.avm` is packed as a library (`packbeam --lib`): it must contain no start module.
- Board atom for the M5StickC Plus 2 is `stick_cplus2` (follows `atomvm_m5`'s `stick_cplus`). Native screen is 135 wide by 240 tall at rotation 0; odd rotations swap width and height.
- JS to Erlang messages are plain strings cast to the registered process `m5_emu_input`: `board:<atom>:<w>:<h>`, `<btn>:down`, `<btn>:up` with `<btn>` in `a b c pwr ext`, and `batt:<0-100>`.
- Erlang to JS calls are `m5emu.exec(<json array of commands>)`, `m5emu.boardReady()`, each via `emscripten:run_script(Script, [main_thread, async])`.
- Text renders with the 6x8 LovyanGFX `Font0` glyphs, white on opaque black, top-left datum, wrap on X, no wrap or scroll on Y (M5GFX defaults; `atomvm_m5` exposes no text color setter).
- Flash offsets: runtime image at `0x1000`, app `.avm` at `0x250000`. Partition table is 8 MB with an `apps` data partition at `0x350000` of size `0x4B0000`.
- Browser page needs COOP `same-origin` and COEP `require-corp`; the dev server sets headers, GitHub Pages uses `coi-serviceworker`.
- Unsupported `atomvm_m5` functions return `{error, unsupported}`; never `undef`.
- Node 22, pnpm 10, Erlang 27.3.4, Elixir 1.18.4-otp-27, rebar3 3.25.0 as pinned in `mise.toml`.

## Review Focus

1. A `.avm` whose start module crashes at boot: the page must show stderr and a restart control, not a blank canvas (Task 8 test `vm.test.ts` "exit with error surfaces stderr").
2. `m5:update/0` called before any button event arrived: every `was_*` getter must be `false` and `is_released/0` `true` (Task 4 test `m5_emu_input_tests` "fresh state").
3. Drawing outside the screen (negative or oversize rectangles, text past the right edge): renderer clips and never throws (Task 7 test `renderer.test.ts` "clipping").
4. Installer connected to a non-ESP32 chip (an S3 or C3): refuse before writing (Task 9 test `installer.test.ts` "wrong chip refuses").
5. Two `.avm` loads in one page session (user drops a second file): the VM restarts cleanly with the new app and the old one is not still drawing (Task 8 test `loader.test.ts` "replace app" plus e2e in Task 11).

---

## File structure

```
boards/m5stickc_plus2/board.json           board profile (data only)
boards/m5stickc_plus2/device.svg           device frame with button hotspots
boards/schema.json                         JSON schema for profiles
m5_emu/rebar.config                        rebar3 + atomvm plugin
m5_emu/src/m5_emu.app.src
m5_emu/src/m5.erl                          begin_/get_board/update
m5_emu/src/m5_display.erl                  public display API (thin)
m5_emu/src/m5_btn_a.erl .. m5_btn_ext.erl  public button APIs (thin)
m5_emu/src/m5_speaker.erl m5_power.erl m5_rtc.erl m5_imu.erl gpio.erl
m5_emu/src/m5_emu_btn.erl                  pure Button_Class port
m5_emu/src/m5_emu_cmd.erl                  command → JSON encoding
m5_emu/src/m5_emu_display.erl              display state + batching (gen_server)
m5_emu/src/m5_emu_input.erl                events, buttons, battery, board (gen_server)
m5_emu/src/m5_emu_bridge.erl               behaviour: run_script/1
m5_emu/src/m5_emu_bridge_emscripten.erl    real bridge
m5_emu/test/*_tests.erl                    eunit
m5_emu/test/support/m5_emu_bridge_test.erl mock bridge
m5_emu/test/atomvm_m5_api.txt              pinned API list for the drift test
m5_emu/test/smoke_app/                     Erlang app run under AtomVM-node
m5_emu/test/node/smoke.mjs                 node harness
web/ (Vite)  src/board.ts protocol.ts framebuffer.ts font0.ts renderer.ts canvas.ts
             src/vm.ts loader.ts input.ts audio.ts console.ts installer.ts main.ts
             public/coi-serviceworker.js  public/atomvm/ (fetched, gitignored)
             e2e/clock.spec.ts
firmware/m5stickc_plus2/partitions.csv sdkconfig.m5stickc_plus2 patches/ manifest.json
.github/workflows/firmware.yml ci.yml pages.yml
m5_emu_mix/                                mix m5.emulate
examples/clock/                            Elixir reference app
scripts/setup.sh dev.sh test.sh firmware.sh fetch-atomvm.sh build-m5-emu.sh import-font0.mjs
```

---

### Task 1: Board profile, web scaffold, tooling scripts

**Files:**
- Create: `boards/m5stickc_plus2/board.json`, `boards/schema.json`, `boards/m5stickc_plus2/device.svg`
- Create: `web/package.json`, `web/vite.config.ts`, `web/tsconfig.json`, `web/index.html`, `web/src/board.ts`, `web/src/protocol.ts`
- Create: `web/test/board.test.ts`, `web/test/protocol.test.ts`
- Create: `scripts/setup.sh`, `scripts/test.sh`, `scripts/fetch-atomvm.sh`, `.gitignore`

**Interfaces:**
- Produces `BoardProfile` (TypeScript):
  ```ts
  export interface BoardButton { id: "a"|"b"|"c"|"pwr"|"ext"; label: string; key: string; x: number; y: number }
  export interface BoardProfile {
    id: string; name: string; boardAtom: string;
    screen: { width: number; height: number; scale: number };
    buttons: BoardButton[];
    peripherals: { speaker: boolean; led: boolean; battery: boolean };
    chip: string;                 // esptool chip name, "ESP32"
    firmwareManifest: string;     // URL
    appOffset: number;            // 0x250000
    deviceImage: string;          // "device.svg"
  }
  export function parseBoardProfile(json: unknown): BoardProfile   // throws Error with field name
  export async function loadBoardProfile(id: string, base?: string): Promise<BoardProfile>
  ```
- Produces `protocol.ts`:
  ```ts
  export type Command = [string, ...(number | string)[]];
  export const INPUT_PROCESS = "m5_emu_input";
  export function buttonMessage(id: string, down: boolean): string   // "a:down"
  export function batteryMessage(percent: number): string            // "batt:73", clamps 0..100
  export function boardMessage(p: BoardProfile): string              // "board:stick_cplus2:135:240"
  ```

- [ ] **Step 1: Write the board profile and schema**

`boards/m5stickc_plus2/board.json`:
```json
{
  "id": "m5stickc_plus2",
  "name": "M5StickC Plus 2",
  "boardAtom": "stick_cplus2",
  "screen": { "width": 135, "height": 240, "scale": 3 },
  "buttons": [
    { "id": "a",   "label": "A",     "key": "a", "x": 67,  "y": 300 },
    { "id": "b",   "label": "B",     "key": "b", "x": 150, "y": 160 },
    { "id": "pwr", "label": "Power", "key": "p", "x": -15, "y": 160 }
  ],
  "peripherals": { "speaker": true, "led": true, "battery": true },
  "chip": "ESP32",
  "firmwareManifest": "https://github.com/tomashco/atomvm_watch/releases/latest/download/manifest-m5stickc_plus2.json",
  "appOffset": 2424832,
  "deviceImage": "device.svg"
}
```
`boards/schema.json` (JSON Schema draft 2020-12) requiring every key above; `buttons[].id` enum `["a","b","c","pwr","ext"]`; `screen.width/height` integers ≥ 1; `appOffset` integer ≥ 0.

`boards/m5stickc_plus2/device.svg`: a 200x400 rounded rectangle (fill `#f36b21`) with a 135x240 transparent window at (32, 60); three circles for buttons at the coordinates above with `id="btn-a"`, `id="btn-b"`, `id="btn-pwr"`.

- [ ] **Step 2: Scaffold the Vite project**

```bash
cd web && pnpm init && pnpm add -D vite typescript vitest @types/node ajv
```
`web/package.json` scripts: `"dev": "vite", "build": "vite build", "preview": "vite preview", "test": "vitest run"`.

`web/vite.config.ts`:
```ts
import { defineConfig } from "vite";
const coop = { "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp" };
export default defineConfig({
  base: "./",
  server: { headers: coop, fs: { allow: [".."] } },
  preview: { headers: coop },
  build: { target: "es2022" },
  test: { environment: "node", include: ["test/**/*.test.ts"] },
});
```
`web/tsconfig.json`: `"target": "ES2022", "module": "ESNext", "moduleResolution": "Bundler", "strict": true, "lib": ["ES2022","DOM"]`.

`web/index.html` for now: `<!doctype html><title>atomvm_watch</title><div id="app"></div><script type="module" src="/src/main.ts"></script>` and `web/src/main.ts` with `console.log("atomvm_watch")`.

- [ ] **Step 3: Write failing tests for the profile parser and protocol**

`web/test/board.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { parseBoardProfile } from "../src/board";
const raw = JSON.parse(readFileSync(new URL("../../boards/m5stickc_plus2/board.json", import.meta.url), "utf8"));
describe("parseBoardProfile", () => {
  it("accepts the m5stickc_plus2 profile", () => {
    const p = parseBoardProfile(raw);
    expect(p.boardAtom).toBe("stick_cplus2");
    expect(p.screen).toEqual({ width: 135, height: 240, scale: 3 });
    expect(p.appOffset).toBe(0x250000);
    expect(p.buttons.map(b => b.id)).toEqual(["a", "b", "pwr"]);
  });
  it("rejects a profile missing the screen", () => {
    const { screen, ...rest } = raw;
    expect(() => parseBoardProfile(rest)).toThrow(/screen/);
  });
  it("rejects an unknown button id", () => {
    const bad = { ...raw, buttons: [{ id: "x", label: "X", key: "x", x: 0, y: 0 }] };
    expect(() => parseBoardProfile(bad)).toThrow(/buttons/);
  });
});
```
`web/test/protocol.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { buttonMessage, batteryMessage, boardMessage } from "../src/protocol";
import { parseBoardProfile } from "../src/board";
import { readFileSync } from "node:fs";
const p = parseBoardProfile(JSON.parse(readFileSync(new URL("../../boards/m5stickc_plus2/board.json", import.meta.url), "utf8")));
describe("protocol", () => {
  it("formats button events", () => {
    expect(buttonMessage("a", true)).toBe("a:down");
    expect(buttonMessage("pwr", false)).toBe("pwr:up");
  });
  it("clamps battery", () => {
    expect(batteryMessage(73)).toBe("batt:73");
    expect(batteryMessage(140)).toBe("batt:100");
    expect(batteryMessage(-3)).toBe("batt:0");
  });
  it("formats the board handshake", () => {
    expect(boardMessage(p)).toBe("board:stick_cplus2:135:240");
  });
});
```

- [ ] **Step 4: Run tests, verify they fail**

Run: `cd web && pnpm test`
Expected: FAIL, cannot resolve `../src/board` and `../src/protocol`.

- [ ] **Step 5: Implement `board.ts` and `protocol.ts`**

`web/src/board.ts`:
```ts
import Ajv from "ajv";
import schema from "../../boards/schema.json";
export interface BoardButton { id: "a" | "b" | "c" | "pwr" | "ext"; label: string; key: string; x: number; y: number }
export interface BoardProfile {
  id: string; name: string; boardAtom: string;
  screen: { width: number; height: number; scale: number };
  buttons: BoardButton[];
  peripherals: { speaker: boolean; led: boolean; battery: boolean };
  chip: string; firmwareManifest: string; appOffset: number; deviceImage: string;
}
const validate = new Ajv({ allErrors: true }).compile(schema);
export function parseBoardProfile(json: unknown): BoardProfile {
  if (!validate(json)) {
    const e = validate.errors![0];
    throw new Error(`invalid board profile at ${e.instancePath || "/"} (${e.message}) — ${JSON.stringify(validate.errors)}`);
  }
  return json as BoardProfile;
}
export async function loadBoardProfile(id: string, base = import.meta.env.BASE_URL): Promise<BoardProfile> {
  const res = await fetch(`${base}boards/${id}/board.json`);
  if (!res.ok) throw new Error(`board profile ${id} not found (${res.status})`);
  return parseBoardProfile(await res.json());
}
```
The error message must contain the failing property name: with Ajv, a missing `screen` reports `instancePath ""` and `message "must have required property 'screen'"`, so the regex `/screen/` matches; an invalid button id reports `instancePath "/buttons/0/id"`.

`web/src/protocol.ts`:
```ts
import type { BoardProfile } from "./board";
export type Command = [string, ...(number | string)[]];
export const INPUT_PROCESS = "m5_emu_input";
export function buttonMessage(id: string, down: boolean): string { return `${id}:${down ? "down" : "up"}`; }
export function batteryMessage(percent: number): string {
  const p = Math.max(0, Math.min(100, Math.round(percent)));
  return `batt:${p}`;
}
export function boardMessage(p: BoardProfile): string { return `board:${p.boardAtom}:${p.screen.width}:${p.screen.height}`; }
```
Add `"resolveJsonModule": true` to `tsconfig.json`. Vite serves `boards/` through a symlink `web/public/boards -> ../../boards` (create it: `ln -s ../../boards web/public/boards`).

- [ ] **Step 6: Run tests, verify they pass**

Run: `cd web && pnpm test`
Expected: PASS, 6 tests.

- [ ] **Step 7: Tooling scripts**

`scripts/fetch-atomvm.sh` (downloads the pinned wasm builds, verifies sha256, idempotent):
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ATOMVM_VERSION:?set by mise}"
BASE="https://github.com/atomvm/AtomVM/releases/download/${ATOMVM_VERSION}"
fetch() { # $1 asset name, $2 destination path
  local name="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ] && [ -f "$dest.sha256" ]; then return 0; fi
  curl -fsSL "$BASE/$name" -o "$dest"
  curl -fsSL "$BASE/$name.sha256" -o "$dest.sha256"
  (cd "$(dirname "$dest")" && sed "s#$name#$(basename "$dest")#" "$(basename "$dest").sha256" | shasum -a 256 -c -)
}
fetch "AtomVM-web-${ATOMVM_VERSION}.mjs"  web/public/atomvm/AtomVM.mjs
fetch "AtomVM-web-${ATOMVM_VERSION}.wasm" web/public/atomvm/AtomVM.wasm
fetch "AtomVM-node-${ATOMVM_VERSION}.mjs"  vendor/atomvm/AtomVM-node.mjs
fetch "AtomVM-node-${ATOMVM_VERSION}.wasm" vendor/atomvm/AtomVM-node.wasm
echo "AtomVM ${ATOMVM_VERSION} wasm builds ready"
```
The web `.mjs` locates its `.wasm` next to itself by default; keeping both under `web/public/atomvm/` with the names `AtomVM.mjs` and `AtomVM.wasm` satisfies that. Verify after download: `grep -o 'AtomVM[^"]*\.wasm' web/public/atomvm/AtomVM.mjs | head -1` must print `AtomVM.wasm`; if it prints the versioned name, rename the `.wasm` to match instead.

`scripts/setup.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/fetch-atomvm.sh
(cd web && pnpm install)
[ -d m5_emu ] && (cd m5_emu && rebar3 get-deps) || true
[ -d examples/clock ] && (cd examples/clock && mix deps.get) || true
[ -d m5_emu_mix ] && (cd m5_emu_mix && mix deps.get) || true
echo "setup complete"
```
`scripts/test.sh` (extended by later tasks):
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
(cd web && pnpm test)
```
`.gitignore`: `web/node_modules/ web/dist/ web/public/atomvm/ vendor/ **/_build/ **/deps/ *.avm !web/e2e/fixtures/*.avm web/test-results/ web/playwright-report/`.
`chmod +x scripts/*.sh`.

- [ ] **Step 8: Run setup and tests through mise**

Run: `mise install && mise run setup && mise run test`
Expected: wasm files downloaded with "ready" line; vitest PASS.

- [ ] **Step 9: Commit**

```bash
git add boards web scripts .gitignore
git commit -m "feat: board profile, web scaffold, tooling scripts"
```

---

### Task 2: `m5_emu` project and the button state machine

**Files:**
- Create: `m5_emu/rebar.config`, `m5_emu/src/m5_emu.app.src`, `m5_emu/src/m5_emu_btn.erl`
- Test: `m5_emu/test/m5_emu_btn_tests.erl`
- Modify: `scripts/test.sh`

**Interfaces:**
- Produces:
  ```erlang
  -record(btn, {last_msec = 0, last_clicked = 0, msec_debounce = 10, msec_hold = 500,
                last_hold_period = 0, state = nochange, raw_press = false, press = 0,
                old_press = 0, click_count = 0, last_change = 0, last_raw_change = 0}).
  -type btn() :: #btn{}.
  new() -> btn().
  set_raw_state(btn(), Msec :: non_neg_integer(), Pressed :: boolean()) -> btn().
  %% getters, each (btn()) -> boolean() | integer():
  was_clicked/1 was_hold/1 was_single_clicked/1 was_double_clicked/1 was_decide_click_count/1
  get_click_count/1 is_holding/1 was_change_pressed/1 is_pressed/1 is_released/1 was_pressed/1
  was_released/1 was_released_after_hold/1 last_change/1 get_debounce_thresh/1 get_hold_thresh/1
  get_update_msec/1
  %% with an argument:
  was_released_for(btn(), Ms) -> boolean().  pressed_for(btn(), Ms) -> boolean().  release_for(btn(), Ms) -> boolean().
  set_debounce_thresh(btn(), Ms) -> btn().   set_hold_thresh(btn(), Ms) -> btn().
  ```
  The record lives in `m5_emu/include/m5_emu_btn.hrl`.

- [ ] **Step 1: Create the rebar3 project**

`m5_emu/rebar.config`:
```erlang
{erl_opts, [debug_info, warnings_as_errors]}.
{deps, []}.
{plugins, [{atomvm_rebar3_plugin, "0.7.5"}]}.
{eunit_opts, [verbose]}.
{profiles, [{test, [{erl_opts, [debug_info, nowarn_export_all]}, {extra_src_dirs, ["test/support"]}]}]}.
```
`m5_emu/src/m5_emu.app.src`:
```erlang
{application, m5_emu, [
    {description, "atomvm_m5 API for AtomVM's emscripten platform"},
    {vsn, "0.1.0"}, {registered, [m5_emu_input, m5_emu_display]},
    {applications, [kernel, stdlib]}, {env, []}, {licenses, ["Apache-2.0"]}
]}.
```

- [ ] **Step 2: Write failing tests for the state machine**

The scenarios come from M5Unified `Button_Class.cpp` (0.2.10). Time is passed explicitly, so tests are deterministic.

`m5_emu/test/m5_emu_btn_tests.erl`:
```erlang
-module(m5_emu_btn_tests).
-include_lib("eunit/include/eunit.hrl").

%% Feed a list of {Msec, Pressed} samples, return the final record.
feed(Samples) -> lists:foldl(fun({T, P}, B) -> m5_emu_btn:set_raw_state(B, T, P) end, m5_emu_btn:new(), Samples).

fresh_state_test() ->
    B = m5_emu_btn:new(),
    ?assertNot(m5_emu_btn:is_pressed(B)),
    ?assert(m5_emu_btn:is_released(B)),
    ?assertNot(m5_emu_btn:was_pressed(B)),
    ?assertNot(m5_emu_btn:was_released(B)),
    ?assertEqual(0, m5_emu_btn:get_click_count(B)).

press_is_debounced_test() ->
    %% Raw level goes high at t=0 and is sampled again at t=5 (< 10 ms debounce): still released.
    B5 = feed([{0, true}, {5, true}]),
    ?assertNot(m5_emu_btn:is_pressed(B5)),
    %% At t=10 the level has been stable for 10 ms: pressed, and was_pressed for this cycle.
    B10 = m5_emu_btn:set_raw_state(B5, 10, true),
    ?assert(m5_emu_btn:is_pressed(B10)),
    ?assert(m5_emu_btn:was_pressed(B10)),
    %% One more cycle: still pressed, but the edge flag is gone.
    B20 = m5_emu_btn:set_raw_state(B10, 20, true),
    ?assert(m5_emu_btn:is_pressed(B20)),
    ?assertNot(m5_emu_btn:was_pressed(B20)).

click_test() ->
    B = feed([{0, true}, {10, true}, {100, false}, {110, false}]),
    ?assert(m5_emu_btn:was_released(B)),
    ?assert(m5_emu_btn:was_clicked(B)),
    ?assertEqual(1, m5_emu_btn:get_click_count(B)),
    %% After the hold timeout (500 ms) with no second click, the count is decided.
    B2 = m5_emu_btn:set_raw_state(B, 700, false),
    ?assert(m5_emu_btn:was_decide_click_count(B2)),
    ?assert(m5_emu_btn:was_single_clicked(B2)),
    B3 = m5_emu_btn:set_raw_state(B2, 710, false),
    ?assertNot(m5_emu_btn:was_single_clicked(B3)),
    ?assertEqual(0, m5_emu_btn:get_click_count(B3)).

double_click_test() ->
    B = feed([{0, true}, {10, true}, {100, false}, {110, false},
              {200, true}, {210, true}, {300, false}, {310, false}, {900, false}]),
    ?assert(m5_emu_btn:was_double_clicked(B)).

hold_test() ->
    B = feed([{0, true}, {10, true}, {300, true}]),
    ?assertNot(m5_emu_btn:is_holding(B)),
    B2 = m5_emu_btn:set_raw_state(B, 520, true),
    ?assert(m5_emu_btn:is_holding(B2)),
    ?assert(m5_emu_btn:was_hold(B2)),
    ?assert(m5_emu_btn:pressed_for(B2, 500)),
    B3 = feed([{0, true}, {10, true}, {520, true}, {600, false}, {610, false}]),
    ?assert(m5_emu_btn:was_released_after_hold(B3)),
    ?assert(m5_emu_btn:was_released_for(B3, 500)),
    ?assertNot(m5_emu_btn:was_clicked(B3)).

thresholds_test() ->
    B = m5_emu_btn:set_hold_thresh(m5_emu_btn:set_debounce_thresh(m5_emu_btn:new(), 0), 100),
    ?assertEqual(0, m5_emu_btn:get_debounce_thresh(B)),
    ?assertEqual(100, m5_emu_btn:get_hold_thresh(B)),
    B2 = feed_from(B, [{0, true}, {1, true}, {150, true}]),
    ?assert(m5_emu_btn:is_holding(B2)).

feed_from(B0, Samples) -> lists:foldl(fun({T, P}, B) -> m5_emu_btn:set_raw_state(B, T, P) end, B0, Samples).
```

- [ ] **Step 3: Run tests, verify they fail**

Run: `cd m5_emu && rebar3 eunit`
Expected: FAIL, `m5_emu_btn` undefined.

- [ ] **Step 4: Implement the port**

`m5_emu/include/m5_emu_btn.hrl`: the record from Interfaces.

`m5_emu/src/m5_emu_btn.erl`:
```erlang
-module(m5_emu_btn).
-include("m5_emu_btn.hrl").
-export([new/0, set_raw_state/3,
         was_clicked/1, was_hold/1, was_single_clicked/1, was_double_clicked/1,
         was_decide_click_count/1, get_click_count/1, is_holding/1, was_change_pressed/1,
         is_pressed/1, is_released/1, was_pressed/1, was_released/1, was_released_after_hold/1,
         was_released_for/2, pressed_for/2, release_for/2,
         set_debounce_thresh/2, set_hold_thresh/2, last_change/1,
         get_debounce_thresh/1, get_hold_thresh/1, get_update_msec/1]).
-export_type([btn/0]).
-type btn() :: #btn{}.

new() -> #btn{}.

%% Port of Button_Class::setRawState (M5Unified 0.2.10).
set_raw_state(#btn{} = B0, Msec, Press) ->
    DisableDb = (Msec - B0#btn.last_msec) > B0#btn.msec_debounce,
    OldPress = B0#btn.press,
    B1 = B0#btn{old_press = OldPress},
    B2 = case B1#btn.raw_press =/= Press of
             true -> B1#btn{raw_press = Press, last_raw_change = Msec};
             false -> B1
         end,
    {B3, State} =
        case DisableDb orelse (Msec - B2#btn.last_raw_change >= B2#btn.msec_debounce) of
            true ->
                Bc = case Press =/= (OldPress =/= 0) of
                         true -> B2#btn{last_change = Msec};
                         false -> B2
                     end,
                case Press of
                    true ->
                        Hold = Msec - Bc#btn.last_change,
                        Bh = Bc#btn{last_hold_period = Hold},
                        if OldPress =:= 0 -> {Bh#btn{press = 1}, nochange};
                           OldPress =:= 1, Hold >= Bh#btn.msec_hold -> {Bh#btn{press = 2}, hold};
                           true -> {Bh, nochange}
                        end;
                    false ->
                        Br = Bc#btn{press = 0},
                        case OldPress of 1 -> {Br, clicked}; _ -> {Br, nochange} end
                end;
            false -> {B2, nochange}
        end,
    set_state(B3, Msec, State).

%% Port of Button_Class::setState.
set_state(#btn{} = B0, Msec, State0) ->
    B1 = case B0#btn.state of decide_click_count -> B0#btn{click_count = 0}; _ -> B0 end,
    B2 = B1#btn{last_msec = Msec},
    Timeout = (Msec - B2#btn.last_clicked) > B2#btn.msec_hold,
    {B3, State} =
        case State0 of
            nochange when Timeout, B2#btn.press =:= 0, B2#btn.click_count =/= 0 ->
                case B2#btn.old_press =:= 0 andalso B2#btn.state =:= nochange of
                    true -> {B2, decide_click_count};
                    false -> {B2#btn{click_count = 0}, nochange}
                end;
            clicked -> {B2#btn{click_count = B2#btn.click_count + 1, last_clicked = Msec}, clicked};
            Other -> {B2, Other}
        end,
    B3#btn{state = State}.

was_clicked(#btn{state = S}) -> S =:= clicked.
was_hold(#btn{state = S}) -> S =:= hold.
was_single_clicked(#btn{state = S, click_count = C}) -> S =:= decide_click_count andalso C =:= 1.
was_double_clicked(#btn{state = S, click_count = C}) -> S =:= decide_click_count andalso C =:= 2.
was_decide_click_count(#btn{state = S}) -> S =:= decide_click_count.
get_click_count(#btn{click_count = C}) -> C.
is_holding(#btn{press = P}) -> P =:= 2.
was_change_pressed(#btn{press = P, old_press = O}) -> (P =/= 0) =/= (O =/= 0).
is_pressed(#btn{press = P}) -> P =/= 0.
is_released(#btn{press = P}) -> P =:= 0.
was_pressed(#btn{press = P, old_press = O}) -> O =:= 0 andalso P =/= 0.
was_released(#btn{press = P, old_press = O}) -> O =/= 0 andalso P =:= 0.
was_released_after_hold(#btn{press = P, old_press = O}) -> P =:= 0 andalso O =:= 2.
was_released_for(#btn{press = P, old_press = O, last_hold_period = H}, Ms) -> O =/= 0 andalso P =:= 0 andalso H >= Ms.
pressed_for(#btn{press = P, last_msec = T, last_change = C}, Ms) -> P =/= 0 andalso T - C >= Ms.
release_for(#btn{press = P, last_msec = T, last_change = C}, Ms) -> P =:= 0 andalso T - C >= Ms.
set_debounce_thresh(B, Ms) -> B#btn{msec_debounce = Ms}.
set_hold_thresh(B, Ms) -> B#btn{msec_hold = Ms}.
last_change(#btn{last_change = C}) -> C.
get_debounce_thresh(#btn{msec_debounce = D}) -> D.
get_hold_thresh(#btn{msec_hold = H}) -> H.
get_update_msec(#btn{last_msec = T}) -> T.
```

- [ ] **Step 5: Run tests, verify they pass**

Run: `cd m5_emu && rebar3 eunit`
Expected: PASS, 6 tests. If `press_is_debounced_test` fails at t=10, check the `>=` in the debounce comparison (C uses `msec - _lastRawChange >= _msecDebounce`).

- [ ] **Step 6: Wire into `scripts/test.sh` and commit**

Append `(cd m5_emu && rebar3 eunit)` to `scripts/test.sh` before the web line.
```bash
git add m5_emu scripts/test.sh
git commit -m "feat(m5_emu): rebar3 project and Button_Class port"
```

---

### Task 3: Display state, command encoding and the `m5_display` API

**Files:**
- Create: `m5_emu/src/m5_emu_bridge.erl`, `m5_emu/src/m5_emu_bridge_emscripten.erl`, `m5_emu/src/m5_emu_cmd.erl`, `m5_emu/src/m5_emu_display.erl`, `m5_emu/src/m5_display.erl`
- Create: `m5_emu/test/support/m5_emu_bridge_test.erl`, `m5_emu/test/m5_emu_cmd_tests.erl`, `m5_emu/test/m5_emu_display_tests.erl`

**Interfaces:**
- Produces:
  ```erlang
  %% m5_emu_bridge behaviour
  -callback run_script(iodata()) -> ok.
  %% m5_emu_bridge_emscripten:run_script(S) -> emscripten:run_script(S, [main_thread, async]).
  %% m5_emu_bridge_test:run_script(S) -> whereis(m5_emu_test_sink) ! {script, iolist_to_binary(S)}, ok.

  %% m5_emu_cmd
  -type command() :: tuple().               % {fill_rect, X, Y, W, H, Color}
  encode([command()]) -> iodata().           % JSON array of arrays, e.g. [["fill_rect",0,0,10,10,16711680]]
  exec_script([command()]) -> iodata().      % <<"m5emu.exec(">> ++ encode(Cmds) ++ <<")">>
  to_rgb888(m5_display:color()) -> 0..16777215.

  %% m5_emu_display (gen_server, registered m5_emu_display)
  start_link(Bridge :: module()) -> {ok, pid()}.
  configure(Width, Height) -> ok.            % native size from the board profile
  cmd(command()) -> ok.                       % buffer or flush depending on write batch
  start_write() -> ok.  end_write() -> ok.
  get(width | height | rotation | cursor | text_size | color | base_color | sleeping) -> term().
  set(rotation | cursor | text_size | color | base_color | sleeping, term()) -> ok.
  reset() -> ok.                              % back to defaults, keeps Bridge and native size
  ```
- `m5_display` exposes every function in `atomvm_m5`'s `m5_display.erl` (the 90 exports listed in the spec research; copy the list from the pinned commit's `src/m5_display.erl`).

- [ ] **Step 1: Write failing tests for encoding and color conversion**

`m5_emu/test/m5_emu_cmd_tests.erl`:
```erlang
-module(m5_emu_cmd_tests).
-include_lib("eunit/include/eunit.hrl").

encode_test() ->
    Json = iolist_to_binary(m5_emu_cmd:encode([{fill_rect, 0, 0, 10, 20, 16#FF0000}, {print, <<"Hi \"there\"\n">>}])),
    ?assertEqual(<<"[[\"fill_rect\",0,0,10,20,16711680],[\"print\",\"Hi \\\"there\\\"\\n\"]]">>, Json).

exec_script_test() ->
    ?assertEqual(<<"m5emu.exec([[\"sleep\"]])">>, iolist_to_binary(m5_emu_cmd:exec_script([{sleep}]))).

negative_and_float_test() ->
    ?assertEqual(<<"[[\"set_text_size\",-1,2.5]]">>, iolist_to_binary(m5_emu_cmd:encode([{set_text_size, -1, 2.5}]))).

color_test() ->
    ?assertEqual(16#FF0000, m5_emu_cmd:to_rgb888(16#FF0000)),
    ?assertEqual(16#FF0000, m5_emu_cmd:to_rgb888({rgb888, 16#FF0000})),
    ?assertEqual(16#FF0000, m5_emu_cmd:to_rgb888({rgb, {255, 0, 0}})),
    %% RGB565 0xF800 is pure red; low bits are replicated so 0x1F -> 0xFF.
    ?assertEqual(16#FF0000, m5_emu_cmd:to_rgb888({rgb565, 16#F800})),
    ?assertEqual(16#00FF00, m5_emu_cmd:to_rgb888({rgb565, 16#07E0})),
    ?assertEqual(16#0000FF, m5_emu_cmd:to_rgb888({rgb565, 16#001F})).
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `cd m5_emu && rebar3 eunit --module=m5_emu_cmd_tests`
Expected: FAIL, `m5_emu_cmd` undefined.

- [ ] **Step 3: Implement `m5_emu_cmd` and the bridge modules**

`m5_emu/src/m5_emu_cmd.erl`:
```erlang
-module(m5_emu_cmd).
-export([encode/1, exec_script/1, to_rgb888/1]).

exec_script(Cmds) -> [<<"m5emu.exec(">>, encode(Cmds), <<")">>].

encode(Cmds) -> [$[, join([encode_cmd(C) || C <- Cmds]), $]].

encode_cmd(Cmd) when is_tuple(Cmd) ->
    [Name | Args] = tuple_to_list(Cmd),
    [$[, join([str(atom_to_binary(Name, utf8)) | [val(A) || A <- Args]]), $]].

val(I) when is_integer(I) -> integer_to_binary(I);
val(F) when is_float(F) -> float_to_binary(F, [{decimals, 4}, compact]);
val(A) when is_atom(A) -> str(atom_to_binary(A, utf8));
val(B) when is_binary(B) -> str(B);
val(L) when is_list(L) -> str(iolist_to_binary(L)).

str(Bin) -> [$", escape(Bin), $"].
escape(<<>>) -> [];
escape(<<$", R/binary>>) -> [<<"\\\"">> | escape(R)];
escape(<<$\\, R/binary>>) -> [<<"\\\\">> | escape(R)];
escape(<<$\n, R/binary>>) -> [<<"\\n">> | escape(R)];
escape(<<$\r, R/binary>>) -> [<<"\\r">> | escape(R)];
escape(<<$\t, R/binary>>) -> [<<"\\t">> | escape(R)];
escape(<<C, R/binary>>) when C < 16#20 -> [io_lib:format("\\u~4.16.0b", [C]) | escape(R)];
escape(<<C, R/binary>>) -> [C | escape(R)].

join([]) -> [];
join([X]) -> [X];
join([X | Rest]) -> [X, $, | join(Rest)].

to_rgb888(I) when is_integer(I) -> I band 16#FFFFFF;
to_rgb888({rgb888, I}) -> I band 16#FFFFFF;
to_rgb888({rgb, {R, G, B}}) -> (R bsl 16) bor (G bsl 8) bor B;
to_rgb888({rgb565, C}) ->
    R5 = (C bsr 11) band 16#1F, G6 = (C bsr 5) band 16#3F, B5 = C band 16#1F,
    R = (R5 bsl 3) bor (R5 bsr 2), G = (G6 bsl 2) bor (G6 bsr 4), B = (B5 bsl 3) bor (B5 bsr 2),
    (R bsl 16) bor (G bsl 8) bor B.
```
`float_to_binary(2.5, [{decimals,4}, compact])` yields `<<"2.5">>`; AtomVM supports `float_to_binary/2` with these options.

`m5_emu/src/m5_emu_bridge.erl`:
```erlang
-module(m5_emu_bridge).
-callback run_script(iodata()) -> ok.
```
`m5_emu/src/m5_emu_bridge_emscripten.erl`:
```erlang
-module(m5_emu_bridge_emscripten).
-behaviour(m5_emu_bridge).
-export([run_script/1]).
run_script(Script) -> emscripten:run_script(Script, [main_thread, async]).
```
`m5_emu/test/support/m5_emu_bridge_test.erl`:
```erlang
-module(m5_emu_bridge_test).
-behaviour(m5_emu_bridge).
-export([run_script/1]).
run_script(Script) -> m5_emu_test_sink ! {script, iolist_to_binary(Script)}, ok.
```
Compiling `m5_emu_bridge_emscripten` on OTP warns nothing: `emscripten` is a remote call resolved at run time.

- [ ] **Step 4: Run the cmd tests, verify they pass**

Run: `cd m5_emu && rebar3 eunit --module=m5_emu_cmd_tests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Write failing tests for the display server and API**

`m5_emu/test/m5_emu_display_tests.erl`:
```erlang
-module(m5_emu_display_tests).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    register(m5_emu_test_sink, self()),
    {ok, Pid} = m5_emu_display:start_link(m5_emu_bridge_test),
    ok = m5_emu_display:configure(135, 240),
    Pid.
cleanup(Pid) -> unlink(Pid), exit(Pid, kill), catch unregister(m5_emu_test_sink), flush().
flush() -> receive _ -> flush() after 0 -> ok end.
script() -> receive {script, S} -> S after 500 -> timeout end.

display_test_() -> {foreach, fun setup/0, fun cleanup/1, [
    fun(_) -> {"immediate flush outside a batch", fun() ->
        ok = m5_display:fill_rect(1, 2, 3, 4, 16#00FF00),
        ?assertEqual(<<"m5emu.exec([[\"fill_rect\",1,2,3,4,65280]])">>, script()) end} end,
    fun(_) -> {"batched flush", fun() ->
        ok = m5_display:start_write(),
        ok = m5_display:fill_rect(0, 0, 1, 1, 0),
        ok = m5_display:draw_pixel(5, 5, 16#FFFFFF),
        ?assertEqual(timeout, script()),
        ok = m5_display:end_write(),
        ?assertEqual(<<"m5emu.exec([[\"fill_rect\",0,0,1,1,0],[\"draw_pixel\",5,5,16777215]])">>, script()) end} end,
    fun(_) -> {"width and height follow rotation", fun() ->
        ?assertEqual(135, m5_display:width()), ?assertEqual(240, m5_display:height()),
        ok = m5_display:set_rotation(1),
        ?assertEqual(<<"m5emu.exec([[\"set_rotation\",1]])">>, script()),
        ?assertEqual(240, m5_display:width()), ?assertEqual(135, m5_display:height()),
        ?assertEqual(1, m5_display:get_rotation()) end} end,
    fun(_) -> {"current color is used by 4-arity fill_rect", fun() ->
        ok = m5_display:set_color({rgb, {0, 0, 255}}),
        ?assertEqual(<<"m5emu.exec([[\"set_color\",255]])">>, script()),
        ok = m5_display:fill_rect(0, 0, 2, 2),
        ?assertEqual(<<"m5emu.exec([[\"fill_rect\",0,0,2,2,255]])">>, script()) end} end,
    fun(_) -> {"cursor and text size are tracked and sent", fun() ->
        ok = m5_display:set_cursor(10, 20), _ = script(),
        ?assertEqual({10, 20}, m5_display:get_cursor()),
        ok = m5_display:set_text_size(2), _ = script(),
        ?assertEqual(16, m5_display:font_height()), ?assertEqual(12, m5_display:font_width()),
        ?assertEqual(5, m5_display:print(<<"hello">>)),
        ?assertEqual(<<"m5emu.exec([[\"print\",\"hello\"]])">>, script()),
        ?assertEqual({10 + 5 * 12, 20}, m5_display:get_cursor()),
        ?assertEqual(1, m5_display:println()),
        ?assertEqual({0, 36}, m5_display:get_cursor()) end} end,
    fun(_) -> {"print wraps at the right edge", fun() ->
        %% width 135, size 1: 22 chars fit (132 px); the 23rd wraps to the next line.
        ok = m5_display:set_cursor(0, 0), _ = script(),
        _ = m5_display:print(binary:copy(<<"x">>, 23)), _ = script(),
        ?assertEqual({6, 8}, m5_display:get_cursor()) end} end,
    fun(_) -> {"unsupported functions return an error tuple", fun() ->
        ?assertEqual({error, unsupported}, m5_display:set_scroll_rect(0, 0, 1, 1)),
        ?assertEqual(ok, m5_display:set_epd_mode(fastest)) end} end
]}.
```

- [ ] **Step 6: Run, verify they fail**

Run: `cd m5_emu && rebar3 eunit --module=m5_emu_display_tests`
Expected: FAIL, `m5_emu_display` undefined.

- [ ] **Step 7: Implement `m5_emu_display`**

`m5_emu/src/m5_emu_display.erl`:
```erlang
-module(m5_emu_display).
-behaviour(gen_server).
-export([start_link/1, configure/2, cmd/1, start_write/0, end_write/0, get/1, set/2, reset/0,
         print/1, println/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(CELL_W, 6).
-define(CELL_H, 8).

-record(st, {bridge, native_w = 135, native_h = 240, rotation = 0, cursor = {0, 0},
             text_size = {1, 1}, color = 16#FFFFFF, base_color = 0, sleeping = false,
             brightness = 128, batch = none}).  % batch :: none | [command()] (reversed)

start_link(Bridge) -> gen_server:start_link({local, ?MODULE}, ?MODULE, Bridge, []).
configure(W, H) -> gen_server:call(?MODULE, {configure, W, H}).
cmd(Cmd) -> gen_server:call(?MODULE, {cmd, Cmd}).
start_write() -> gen_server:call(?MODULE, start_write).
end_write() -> gen_server:call(?MODULE, end_write).
get(Key) -> gen_server:call(?MODULE, {get, Key}).
set(Key, Val) -> gen_server:call(?MODULE, {set, Key, Val}).
reset() -> gen_server:call(?MODULE, reset).
print(Bin) -> gen_server:call(?MODULE, {print, Bin}).
println() -> gen_server:call(?MODULE, println).

init(Bridge) -> {ok, #st{bridge = Bridge}}.

handle_call({configure, W, H}, _From, S) -> {reply, ok, S#st{native_w = W, native_h = H}};
handle_call(reset, _From, #st{bridge = B, native_w = W, native_h = H}) -> {reply, ok, #st{bridge = B, native_w = W, native_h = H}};
handle_call({cmd, Cmd}, _From, S) -> {reply, ok, emit(Cmd, S)};
handle_call(start_write, _From, S) -> {reply, ok, S#st{batch = []}};
handle_call(end_write, _From, #st{batch = none} = S) -> {reply, ok, S};
handle_call(end_write, _From, #st{batch = Cmds} = S) -> {reply, ok, flush(lists:reverse(Cmds), S#st{batch = none})};
handle_call({get, width}, _From, S) -> {reply, width(S), S};
handle_call({get, height}, _From, S) -> {reply, height(S), S};
handle_call({get, rotation}, _From, S) -> {reply, S#st.rotation, S};
handle_call({get, cursor}, _From, S) -> {reply, S#st.cursor, S};
handle_call({get, text_size}, _From, S) -> {reply, S#st.text_size, S};
handle_call({get, color}, _From, S) -> {reply, S#st.color, S};
handle_call({get, base_color}, _From, S) -> {reply, S#st.base_color, S};
handle_call({get, sleeping}, _From, S) -> {reply, S#st.sleeping, S};
handle_call({get, brightness}, _From, S) -> {reply, S#st.brightness, S};
handle_call({set, rotation, R}, _From, S) -> {reply, ok, emit({set_rotation, R}, S#st{rotation = R})};
handle_call({set, cursor, {X, Y}}, _From, S) -> {reply, ok, emit({set_cursor, X, Y}, S#st{cursor = {X, Y}})};
handle_call({set, text_size, {SX, SY}}, _From, S) -> {reply, ok, emit({set_text_size, SX, SY}, S#st{text_size = {SX, SY}})};
handle_call({set, color, C}, _From, S) -> {reply, ok, emit({set_color, C}, S#st{color = C})};
handle_call({set, base_color, C}, _From, S) -> {reply, ok, emit({set_base_color, C}, S#st{base_color = C})};
handle_call({set, sleeping, true}, _From, S) -> {reply, ok, emit({sleep}, S#st{sleeping = true})};
handle_call({set, sleeping, false}, _From, S) -> {reply, ok, emit({wakeup}, S#st{sleeping = false})};
handle_call({set, brightness, Br}, _From, S) -> {reply, ok, emit({set_brightness, Br}, S#st{brightness = Br})};
handle_call({print, Bin}, _From, S) ->
    S1 = emit({print, Bin}, S),
    {reply, byte_size(Bin), S1#st{cursor = advance(Bin, S1)}};
handle_call(println, _From, S) ->
    S1 = emit({println}, S),
    {_, SY} = S#st.text_size, {_, Y} = S#st.cursor,
    {reply, 1, S1#st{cursor = {0, Y + ?CELL_H * SY}}}.

handle_cast(_, S) -> {noreply, S}.

emit(Cmd, #st{batch = none} = S) -> flush([Cmd], S);
emit(Cmd, #st{batch = Cmds} = S) -> S#st{batch = [Cmd | Cmds]}.

flush([], S) -> S;
flush(Cmds, #st{bridge = Bridge} = S) -> ok = Bridge:run_script(m5_emu_cmd:exec_script(Cmds)), S.

width(#st{rotation = R, native_w = W, native_h = H}) -> case R band 1 of 0 -> W; 1 -> H end.
height(#st{rotation = R, native_w = W, native_h = H}) -> case R band 1 of 0 -> H; 1 -> W end.

%% Cursor advance mirrors M5GFX: wrap on X at the right edge, newline resets X. No Y wrap or scroll.
advance(Bin, #st{cursor = {X0, Y0}, text_size = {SX, SY}} = S) ->
    CW = ?CELL_W * SX, CH = ?CELL_H * SY, W = width(S),
    lists:foldl(fun($\n, {_X, Y}) -> {0, Y + CH};
                   ($\r, {_X, Y}) -> {0, Y};
                   (_, {X, Y}) when X + CW > W -> {CW, Y + CH};
                   (_, {X, Y}) -> {X + CW, Y}
                end, {X0, Y0}, binary_to_list(Bin)).
```
Note on `advance`: a glyph that does not fit moves to the next line and is drawn there, so after 22 glyphs at X=132 the 23rd lands at X=0 and leaves the cursor at `{6, 8}`.

- [ ] **Step 8: Implement `m5_display`**

Every function in `atomvm_m5`'s `m5_display` is exported. Pattern: drawing functions call `m5_emu_display:cmd/1` with the current color when the color argument is absent; state functions go through `get/set`; unsupported ones return `{error, unsupported}`.

`m5_emu/src/m5_display.erl` (abridged; implement all 90 exports following these groups):
```erlang
-module(m5_display).
-export([set_epd_mode/1, set_brightness/1, sleep/0, wakeup/0, power_save/1, power_save_on/0, power_save_off/0,
         set_color/1, set_color/3, set_raw_color/1, get_raw_color/0, set_base_color/1, get_base_color/0,
         start_write/0, end_write/0,
         write_pixel/2, write_pixel/3, write_fast_vline/3, write_fast_vline/4, write_fast_hline/3, write_fast_hline/4,
         write_fill_rect/4, write_fill_rect/5, write_fill_rect_preclipped/4, write_fill_rect_preclipped/5,
         write_color/2, push_block/2,
         draw_pixel/2, draw_pixel/3, draw_fast_vline/3, draw_fast_vline/4, draw_fast_hline/3, draw_fast_hline/4,
         fill_rect/4, fill_rect/5, draw_rect/4, draw_rect/5, draw_round_rect/5, draw_round_rect/6,
         fill_round_rect/5, fill_round_rect/6, draw_circle/3, draw_circle/4, fill_circle/3, fill_circle/4,
         draw_ellipse/4, draw_ellipse/5, fill_ellipse/4, fill_ellipse/5, draw_line/4, draw_line/5,
         draw_triangle/6, draw_triangle/7, fill_triangle/6, fill_triangle/7,
         draw_bezier/6, draw_bezier/7, draw_bezier/8, draw_bezier/9,
         fill_screen/0, fill_screen/1, clear/0, clear/1, width/0, height/0, wait_display/0, display_busy/0,
         set_auto_display/1, get_rotation/0, set_rotation/1, set_clip_rect/4, get_clip_rect/0, clear_clip_rect/0,
         set_scroll_rect/4, get_scroll_rect/0, clear_scroll_rect/0, get_cursor/0, set_cursor/2,
         set_text_size/1, set_text_size/2, font_height/0, font_width/0,
         draw_string/3, draw_center_string/3, draw_right_string/3, print/1, println/1, println/0]).

-define(UNSUPPORTED, {error, unsupported}).
color() -> m5_emu_display:get(color).
c(Color) -> m5_emu_cmd:to_rgb888(Color).

set_epd_mode(_) -> ok.
set_brightness(B) -> m5_emu_display:set(brightness, B).
sleep() -> m5_emu_display:set(sleeping, true).
wakeup() -> m5_emu_display:set(sleeping, false).
power_save(_) -> ok.  power_save_on() -> ok.  power_save_off() -> ok.
set_color(Color) -> m5_emu_display:set(color, c(Color)).
set_color(R, G, B) -> set_color({rgb, {R, G, B}}).
set_raw_color(Raw) -> set_color({rgb565, Raw}).
get_raw_color() -> ?UNSUPPORTED.
set_base_color(Color) -> m5_emu_display:set(base_color, c(Color)).
get_base_color() -> m5_emu_display:get(base_color).
start_write() -> m5_emu_display:start_write().
end_write() -> m5_emu_display:end_write().
write_pixel(X, Y) -> draw_pixel(X, Y).           write_pixel(X, Y, C) -> draw_pixel(X, Y, C).
write_fast_vline(X, Y, H) -> draw_fast_vline(X, Y, H).  write_fast_vline(X, Y, H, C) -> draw_fast_vline(X, Y, H, C).
write_fast_hline(X, Y, W) -> draw_fast_hline(X, Y, W).  write_fast_hline(X, Y, W, C) -> draw_fast_hline(X, Y, W, C).
write_fill_rect(X, Y, W, H) -> fill_rect(X, Y, W, H).   write_fill_rect(X, Y, W, H, C) -> fill_rect(X, Y, W, H, C).
write_fill_rect_preclipped(X, Y, W, H) -> fill_rect(X, Y, W, H).
write_fill_rect_preclipped(X, Y, W, H, C) -> fill_rect(X, Y, W, H, C).
write_color(_, _) -> ?UNSUPPORTED.  push_block(_, _) -> ?UNSUPPORTED.
draw_pixel(X, Y) -> draw_pixel(X, Y, color()).
draw_pixel(X, Y, C) -> m5_emu_display:cmd({draw_pixel, X, Y, c(C)}).
draw_fast_vline(X, Y, H) -> draw_fast_vline(X, Y, H, color()).
draw_fast_vline(X, Y, H, C) -> m5_emu_display:cmd({draw_fast_vline, X, Y, H, c(C)}).
draw_fast_hline(X, Y, W) -> draw_fast_hline(X, Y, W, color()).
draw_fast_hline(X, Y, W, C) -> m5_emu_display:cmd({draw_fast_hline, X, Y, W, c(C)}).
fill_rect(X, Y, W, H) -> fill_rect(X, Y, W, H, color()).
fill_rect(X, Y, W, H, C) -> m5_emu_display:cmd({fill_rect, X, Y, W, H, c(C)}).
draw_rect(X, Y, W, H) -> draw_rect(X, Y, W, H, color()).
draw_rect(X, Y, W, H, C) -> m5_emu_display:cmd({draw_rect, X, Y, W, H, c(C)}).
draw_round_rect(X, Y, W, H, R) -> draw_round_rect(X, Y, W, H, R, color()).
draw_round_rect(X, Y, W, H, R, C) -> m5_emu_display:cmd({draw_round_rect, X, Y, W, H, R, c(C)}).
fill_round_rect(X, Y, W, H, R) -> fill_round_rect(X, Y, W, H, R, color()).
fill_round_rect(X, Y, W, H, R, C) -> m5_emu_display:cmd({fill_round_rect, X, Y, W, H, R, c(C)}).
draw_circle(X, Y, R) -> draw_circle(X, Y, R, color()).
draw_circle(X, Y, R, C) -> m5_emu_display:cmd({draw_circle, X, Y, R, c(C)}).
fill_circle(X, Y, R) -> fill_circle(X, Y, R, color()).
fill_circle(X, Y, R, C) -> m5_emu_display:cmd({fill_circle, X, Y, R, c(C)}).
draw_ellipse(X, Y, RX, RY) -> draw_ellipse(X, Y, RX, RY, color()).
draw_ellipse(X, Y, RX, RY, C) -> m5_emu_display:cmd({draw_ellipse, X, Y, RX, RY, c(C)}).
fill_ellipse(X, Y, RX, RY) -> fill_ellipse(X, Y, RX, RY, color()).
fill_ellipse(X, Y, RX, RY, C) -> m5_emu_display:cmd({fill_ellipse, X, Y, RX, RY, c(C)}).
draw_line(X0, Y0, X1, Y1) -> draw_line(X0, Y0, X1, Y1, color()).
draw_line(X0, Y0, X1, Y1, C) -> m5_emu_display:cmd({draw_line, X0, Y0, X1, Y1, c(C)}).
draw_triangle(X0, Y0, X1, Y1, X2, Y2) -> draw_triangle(X0, Y0, X1, Y1, X2, Y2, color()).
draw_triangle(X0, Y0, X1, Y1, X2, Y2, C) -> m5_emu_display:cmd({draw_triangle, X0, Y0, X1, Y1, X2, Y2, c(C)}).
fill_triangle(X0, Y0, X1, Y1, X2, Y2) -> fill_triangle(X0, Y0, X1, Y1, X2, Y2, color()).
fill_triangle(X0, Y0, X1, Y1, X2, Y2, C) -> m5_emu_display:cmd({fill_triangle, X0, Y0, X1, Y1, X2, Y2, c(C)}).
draw_bezier(_, _, _, _, _, _) -> ?UNSUPPORTED.  draw_bezier(_, _, _, _, _, _, _) -> ?UNSUPPORTED.
draw_bezier(_, _, _, _, _, _, _, _) -> ?UNSUPPORTED.  draw_bezier(_, _, _, _, _, _, _, _, _) -> ?UNSUPPORTED.
fill_screen() -> fill_screen(color()).
fill_screen(C) -> m5_emu_display:cmd({fill_screen, c(C)}).
clear() -> clear(get_base_color()).
clear(C) -> m5_emu_display:cmd({fill_screen, c(C)}).
width() -> m5_emu_display:get(width).
height() -> m5_emu_display:get(height).
wait_display() -> ok.  display_busy() -> false.  set_auto_display(_) -> ok.
get_rotation() -> m5_emu_display:get(rotation).
set_rotation(R) when R >= 0, R =< 3 -> m5_emu_display:set(rotation, R).
set_clip_rect(_, _, _, _) -> ?UNSUPPORTED.  get_clip_rect() -> ?UNSUPPORTED.  clear_clip_rect() -> ok.
set_scroll_rect(_, _, _, _) -> ?UNSUPPORTED.  get_scroll_rect() -> ?UNSUPPORTED.  clear_scroll_rect() -> ok.
get_cursor() -> m5_emu_display:get(cursor).
set_cursor(X, Y) -> m5_emu_display:set(cursor, {X, Y}).
set_text_size(S) -> set_text_size(S, S).
set_text_size(SX, SY) -> m5_emu_display:set(text_size, {SX, SY}).
font_height() -> {_, SY} = m5_emu_display:get(text_size), round(8 * SY).
font_width() -> {SX, _} = m5_emu_display:get(text_size), round(6 * SX).
draw_string(S, X, Y) -> m5_emu_display:cmd({draw_string, iolist_to_binary(S), X, Y}), font_width() * iolist_size(S).
draw_center_string(S, X, Y) -> m5_emu_display:cmd({draw_center_string, iolist_to_binary(S), X, Y}), font_width() * iolist_size(S).
draw_right_string(S, X, Y) -> m5_emu_display:cmd({draw_right_string, iolist_to_binary(S), X, Y}), font_width() * iolist_size(S).
print(S) -> m5_emu_display:print(iolist_to_binary(S)).
println(S) -> N = print(S), N + println().
println() -> m5_emu_display:println().
```
`draw_string/3` in `atomvm_m5` returns the drawn width as an integer; keep that.

- [ ] **Step 9: Run tests, verify they pass**

Run: `cd m5_emu && rebar3 eunit`
Expected: PASS, all display and cmd tests.

- [ ] **Step 10: Commit**

```bash
git add m5_emu
git commit -m "feat(m5_emu): display state server, command encoding, m5_display API"
```

---

### Task 4: Input server, `m5` module and the button modules

**Files:**
- Create: `m5_emu/src/m5_emu_input.erl`, `m5_emu/src/m5.erl`, `m5_emu/src/m5_btn_a.erl`, `m5_btn_b.erl`, `m5_btn_c.erl`, `m5_btn_pwr.erl`, `m5_btn_ext.erl`
- Test: `m5_emu/test/m5_emu_input_tests.erl`, `m5_emu/test/m5_tests.erl`

**Interfaces:**
- Consumes `m5_emu_btn` (Task 2), `m5_emu_display:start_link/1, configure/2, reset/0` (Task 3), `m5_emu_bridge` modules.
- Produces:
  ```erlang
  %% m5_emu_input (gen_server, registered m5_emu_input)
  start_link() -> {ok, pid()}.
  await_board(TimeoutMs) -> {ok, {BoardAtom :: atom(), W :: pos_integer(), H :: pos_integer()}} | {error, timeout}.
  board() -> atom() | undefined.
  update() -> ok.                                  % steps every button with the current raw level
  btn(Name :: a|b|c|pwr|ext, Getter :: atom()) -> term().           % apply(m5_emu_btn, Getter, [Rec])
  btn(Name, Getter, Arg :: integer()) -> term().                    % apply(m5_emu_btn, Getter, [Rec, Arg])
  btn_set(Name, Setter :: set_debounce_thresh|set_hold_thresh, Ms) -> ok.
  battery() -> 0..100.                              % default 100
  %% Messages handled: {emscripten, {cast, <<"a:down">>}} etc. per Global Constraints.

  %% m5
  begin_(Opts :: [{bridge, module()} | {clear_display, boolean()} | {atom(), term()}]) -> ok.
  get_board() -> atom().
  update() -> ok.
  %% m5_btn_a .. m5_btn_ext: the 22 functions of atomvm_m5's button NIF table, 0-arity except
  %% was_released_for/1, pressed_for/1, release_for/1, set_debounce_thresh/1, set_hold_thresh/1.
  ```

- [ ] **Step 1: Write failing tests**

`m5_emu/test/m5_emu_input_tests.erl`:
```erlang
-module(m5_emu_input_tests).
-include_lib("eunit/include/eunit.hrl").

setup() -> {ok, Pid} = m5_emu_input:start_link(), Pid.
cleanup(Pid) -> unlink(Pid), exit(Pid, kill).
cast(Bin) -> m5_emu_input ! {emscripten, {cast, Bin}}, m5_emu_input:board().  % board() is a sync call, so the cast is processed

input_test_() -> {foreach, fun setup/0, fun cleanup/1, [
    fun(_) -> {"fresh state", fun() ->
        ok = m5_emu_input:update(),
        ?assertNot(m5_emu_input:btn(a, was_pressed)),
        ?assert(m5_emu_input:btn(a, is_released)),
        ?assertEqual(100, m5_emu_input:battery()) end} end,
    fun(_) -> {"board handshake", fun() ->
        ?assertEqual({error, timeout}, m5_emu_input:await_board(20)),
        cast(<<"board:stick_cplus2:135:240">>),
        ?assertEqual({ok, {stick_cplus2, 135, 240}}, m5_emu_input:await_board(20)),
        ?assertEqual(stick_cplus2, m5_emu_input:board()) end} end,
    fun(_) -> {"button press shows up after update", fun() ->
        m5_emu_input:btn_set(a, set_debounce_thresh, 0),
        cast(<<"a:down">>),
        ok = m5_emu_input:update(),
        ?assert(m5_emu_input:btn(a, is_pressed)),
        ?assert(m5_emu_input:btn(a, was_pressed)),
        ok = m5_emu_input:update(),
        ?assertNot(m5_emu_input:btn(a, was_pressed)),
        cast(<<"a:up">>),
        ok = m5_emu_input:update(),
        ?assert(m5_emu_input:btn(a, was_released)),
        ?assertNot(m5_emu_input:btn(b, was_released)) end} end,
    fun(_) -> {"battery and unknown messages", fun() ->
        cast(<<"batt:42">>), ?assertEqual(42, m5_emu_input:battery()),
        cast(<<"garbage">>), ?assertEqual(42, m5_emu_input:battery()) end} end
]}.
```
`m5_emu/test/m5_tests.erl`:
```erlang
-module(m5_tests).
-include_lib("eunit/include/eunit.hrl").

%% The mock bridge must answer m5emu.boardReady() the way the page does.
responder() ->
    receive {script, <<"m5emu.boardReady()">>} ->
        m5_emu_input ! {emscripten, {cast, <<"board:stick_cplus2:135:240">>}}, responder();
            {script, _} -> responder();
            stop -> ok
    end.

begin_test() ->
    Resp = spawn_link(fun responder/0), register(m5_emu_test_sink, Resp),
    ok = m5:begin_([{bridge, m5_emu_bridge_test}]),
    ?assertEqual(stick_cplus2, m5:get_board()),
    ?assertEqual(135, m5_display:width()),
    ?assertEqual(240, m5_display:height()),
    ok = m5:update(),
    ?assertNot(m5_btn_a:was_pressed()),
    ?assertEqual(10, m5_btn_a:get_debounce_thresh()),
    %% begin_ twice is allowed and resets state
    ok = m5_display:set_rotation(1),
    ok = m5:begin_([{bridge, m5_emu_bridge_test}]),
    ?assertEqual(0, m5_display:get_rotation()),
    Resp ! stop.
```

- [ ] **Step 2: Run, verify they fail**

Run: `cd m5_emu && rebar3 eunit --module=m5_emu_input_tests --module=m5_tests`
Expected: FAIL, modules undefined.

- [ ] **Step 3: Implement `m5_emu_input`**

```erlang
-module(m5_emu_input).
-behaviour(gen_server).
-export([start_link/0, await_board/1, board/0, update/0, btn/2, btn/3, btn_set/3, battery/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(BUTTONS, [a, b, c, pwr, ext]).
-record(st, {board, waiters = [], levels = #{}, btns = #{}, battery = 100}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
await_board(Timeout) -> gen_server:call(?MODULE, {await_board, Timeout}, Timeout + 1000).
board() -> gen_server:call(?MODULE, board).
update() -> gen_server:call(?MODULE, update).
btn(Name, Getter) -> gen_server:call(?MODULE, {btn, Name, Getter, []}).
btn(Name, Getter, Arg) -> gen_server:call(?MODULE, {btn, Name, Getter, [Arg]}).
btn_set(Name, Setter, Ms) -> gen_server:call(?MODULE, {btn_set, Name, Setter, Ms}).
battery() -> gen_server:call(?MODULE, battery).

init([]) ->
    Btns = maps:from_list([{B, m5_emu_btn:new()} || B <- ?BUTTONS]),
    Levels = maps:from_list([{B, false} || B <- ?BUTTONS]),
    {ok, #st{btns = Btns, levels = Levels}}.

handle_call({await_board, _}, _From, #st{board = {_, _, _} = B} = S) -> {reply, {ok, B}, S};
handle_call({await_board, Timeout}, From, #st{waiters = W} = S) ->
    erlang:send_after(Timeout, self(), {await_timeout, From}),
    {noreply, S#st{waiters = [From | W]}};
handle_call(board, _From, #st{board = undefined} = S) -> {reply, undefined, S};
handle_call(board, _From, #st{board = {Atom, _, _}} = S) -> {reply, Atom, S};
handle_call(update, _From, #st{btns = Btns, levels = Levels} = S) ->
    Now = erlang:monotonic_time(millisecond),
    New = maps:map(fun(Name, Rec) -> m5_emu_btn:set_raw_state(Rec, Now, maps:get(Name, Levels)) end, Btns),
    {reply, ok, S#st{btns = New}};
handle_call({btn, Name, Getter, Args}, _From, #st{btns = Btns} = S) ->
    {reply, apply(m5_emu_btn, Getter, [maps:get(Name, Btns) | Args]), S};
handle_call({btn_set, Name, Setter, Ms}, _From, #st{btns = Btns} = S) ->
    {reply, ok, S#st{btns = Btns#{Name := m5_emu_btn:Setter(maps:get(Name, Btns), Ms)}}};
handle_call(battery, _From, S) -> {reply, S#st.battery, S}.

handle_cast(_, S) -> {noreply, S}.

handle_info({emscripten, {cast, Bin}}, S) -> {noreply, handle_message(binary:split(Bin, <<":">>, [global]), S)};
handle_info({await_timeout, From}, #st{waiters = W} = S) ->
    case lists:member(From, W) of
        true -> gen_server:reply(From, {error, timeout}), {noreply, S#st{waiters = lists:delete(From, W)}};
        false -> {noreply, S}
    end;
handle_info(_, S) -> {noreply, S}.

handle_message([<<"board">>, Atom, W, H], #st{waiters = Waiters} = S) ->
    Board = {binary_to_atom(Atom, utf8), binary_to_integer(W), binary_to_integer(H)},
    [gen_server:reply(From, {ok, Board}) || From <- Waiters],
    S#st{board = Board, waiters = []};
handle_message([Btn, Level], #st{levels = Levels} = S) when Level =:= <<"down">>; Level =:= <<"up">> ->
    case button_name(Btn) of
        undefined -> S;
        Name -> S#st{levels = Levels#{Name := Level =:= <<"down">>}}
    end;
handle_message([<<"batt">>, N], S) ->
    try S#st{battery = max(0, min(100, binary_to_integer(N)))} catch error:badarg -> S end;
handle_message(_, S) -> S.

button_name(<<"a">>) -> a;  button_name(<<"b">>) -> b;  button_name(<<"c">>) -> c;
button_name(<<"pwr">>) -> pwr;  button_name(<<"ext">>) -> ext;  button_name(_) -> undefined.
```
AtomVM supports `binary:split/3` with `global`, `binary_to_atom/2`, `maps:map/2`, `erlang:send_after/3`, dynamic `Module:Fun(...)` calls and `apply/3`.

- [ ] **Step 4: Implement `m5` and the button modules**

`m5_emu/src/m5.erl`:
```erlang
-module(m5).
-export([begin_/1, get_board/0, update/0]).

begin_(Opts) ->
    Bridge = proplists:get_value(bridge, Opts, m5_emu_bridge_emscripten),
    ensure_started(m5_emu_input, fun() -> m5_emu_input:start_link() end),
    ensure_started(m5_emu_display, fun() -> m5_emu_display:start_link(Bridge) end),
    ok = m5_emu_display:reset(),
    ok = Bridge:run_script(<<"m5emu.boardReady()">>),
    case m5_emu_input:await_board(5000) of
        {ok, {_Board, W, H}} -> ok = m5_emu_display:configure(W, H);
        {error, timeout} -> erlang:error({m5_emu, board_handshake_timeout})
    end,
    case proplists:get_value(clear_display, Opts, true) of
        true -> m5_display:clear();
        false -> ok
    end.

get_board() ->
    case m5_emu_input:board() of undefined -> undefined; Atom -> Atom end.

update() -> m5_emu_input:update().

ensure_started(Name, Start) ->
    case whereis(Name) of
        undefined -> {ok, Pid} = Start(), unlink(Pid), ok;
        _Pid -> ok
    end.
```
`unlink/1` keeps the servers alive if the caller (the app's start process) exits, which is how an AtomVM app's `start/0` often behaves. Note `m5_emu_display:reset/0` keeps the configured size and bridge; the first `begin_` then `configure/2` sets the size from the handshake.

Button modules are identical except for the name atom. `m5_emu/src/m5_btn_a.erl`:
```erlang
-module(m5_btn_a).
-define(BTN, a).
-export([was_clicked/0, was_hold/0, was_single_clicked/0, was_double_clicked/0, was_decide_click_count/0,
         get_click_count/0, is_holding/0, was_change_pressed/0, is_pressed/0, is_released/0, was_pressed/0,
         was_released/0, was_released_after_hold/0, was_released_for/1, pressed_for/1, release_for/1,
         set_debounce_thresh/1, set_hold_thresh/1, last_change/0, get_debounce_thresh/0, get_hold_thresh/0,
         get_update_msec/0]).
was_clicked() -> m5_emu_input:btn(?BTN, was_clicked).
was_hold() -> m5_emu_input:btn(?BTN, was_hold).
was_single_clicked() -> m5_emu_input:btn(?BTN, was_single_clicked).
was_double_clicked() -> m5_emu_input:btn(?BTN, was_double_clicked).
was_decide_click_count() -> m5_emu_input:btn(?BTN, was_decide_click_count).
get_click_count() -> m5_emu_input:btn(?BTN, get_click_count).
is_holding() -> m5_emu_input:btn(?BTN, is_holding).
was_change_pressed() -> m5_emu_input:btn(?BTN, was_change_pressed).
is_pressed() -> m5_emu_input:btn(?BTN, is_pressed).
is_released() -> m5_emu_input:btn(?BTN, is_released).
was_pressed() -> m5_emu_input:btn(?BTN, was_pressed).
was_released() -> m5_emu_input:btn(?BTN, was_released).
was_released_after_hold() -> m5_emu_input:btn(?BTN, was_released_after_hold).
was_released_for(Ms) -> m5_emu_input:btn(?BTN, was_released_for, Ms).
pressed_for(Ms) -> m5_emu_input:btn(?BTN, pressed_for, Ms).
release_for(Ms) -> m5_emu_input:btn(?BTN, release_for, Ms).
set_debounce_thresh(Ms) -> m5_emu_input:btn_set(?BTN, set_debounce_thresh, Ms).
set_hold_thresh(Ms) -> m5_emu_input:btn_set(?BTN, set_hold_thresh, Ms).
last_change() -> m5_emu_input:btn(?BTN, last_change).
get_debounce_thresh() -> m5_emu_input:btn(?BTN, get_debounce_thresh).
get_hold_thresh() -> m5_emu_input:btn(?BTN, get_hold_thresh).
get_update_msec() -> m5_emu_input:btn(?BTN, get_update_msec).
```
Create `m5_btn_b.erl`, `m5_btn_c.erl`, `m5_btn_pwr.erl`, `m5_btn_ext.erl` by copying and changing `-module` and `-define(BTN, ...)`. Generate them with a one-off shell loop so they cannot drift:
```bash
cd m5_emu/src && for b in b c pwr ext; do sed "s/m5_btn_a/m5_btn_$b/; s/define(BTN, a)/define(BTN, $b)/" m5_btn_a.erl > m5_btn_$b.erl; done
```

- [ ] **Step 5: Run tests, verify they pass**

Run: `cd m5_emu && rebar3 eunit`
Expected: PASS. If `begin_test` hangs, the responder is not registered before `begin_` runs the handshake; registration happens in the test before `begin_`, so check the mock bridge sends to `m5_emu_test_sink`.

- [ ] **Step 6: Commit**

```bash
git add m5_emu
git commit -m "feat(m5_emu): input server, m5 begin_/update, button modules"
```

---

### Task 5: Speaker, power, LED shim, unsupported stubs and the API drift test

**Files:**
- Create: `m5_emu/src/m5_speaker.erl`, `m5_emu/src/m5_power.erl`, `m5_emu/src/m5_rtc.erl`, `m5_emu/src/m5_imu.erl`, `m5_emu/src/gpio.erl`
- Create: `m5_emu/test/atomvm_m5_api.txt`, `m5_emu/test/m5_emu_api_tests.erl`, `m5_emu/test/m5_peripherals_tests.erl`, `scripts/gen-atomvm-m5-api.sh`

**Interfaces:**
- Consumes `m5_emu_display:cmd/1` for forwarding (`{tone, Freq, Ms, Volume}`, `{stop_tone}`, `{led, on|off}`), `m5_emu_input:battery/0`.
- Produces:
  ```erlang
  m5_speaker: is_enabled/0 -> true. set_volume/1 -> ok. get_volume/0 -> 0..255 (default 64).
              tone/2 (Freq, Ms) tone/3 (Freq, Ms, _Channel) tone/4 (Freq, Ms, _Channel, _Stop) -> ok.
              is_playing/0 -> boolean(). stop/0 -> ok.
  m5_power:   get_battery_level/0 -> 0..100. is_charging/0 -> false. get_type/0 -> unknown.
              deep_sleep/0,1,2 timer_sleep/1 set_battery_charge/1 set_charge_current/1 set_charge_voltage/1 -> {error, unsupported}.
  m5_rtc:     is_enabled/0 -> false; every other export -> {error, unsupported}.
  m5_imu:     is_enabled/0 -> false; get_type/0 -> unknown.
  gpio:       set_pin_mode(19, _) -> ok; digital_write(19, high|low|1|0) -> ok; digital_read(19) -> high|low;
              any other pin -> {error, unsupported}.
  ```

- [ ] **Step 1: Pin the upstream API list**

`scripts/gen-atomvm-m5-api.sh` extracts `Module:Fun/Arity` lines from the pinned `atomvm_m5` stub modules and the button NIF table, and writes `m5_emu/test/atomvm_m5_api.txt`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
REV=968508c77c90af5a0109bcd7f0e28a5fa8624c02
TMP=$(mktemp -d)
for m in m5 m5_display m5_power m5_rtc m5_speaker; do
  curl -fsSL "https://raw.githubusercontent.com/pguyot/atomvm_m5/$REV/src/$m.erl" -o "$TMP/$m.erl"
  erl -noshell -eval "
    {ok, F} = epp:parse_file(\"$TMP/$m.erl\", []),
    Ex = lists:append([L || {attribute, _, export, L} <- F]),
    [io:format(\"$m:~s/~p~n\", [N, A]) || {N, A} <- Ex], halt()."
done > "$TMP/api.txt"
# Button modules have no stub .erl; their 22 functions come from nifs/atomvm_m5_btn.cc.
for b in a b c pwr ext; do
  for f in was_clicked/0 was_hold/0 was_single_clicked/0 was_double_clicked/0 was_decide_click_count/0 \
           get_click_count/0 is_holding/0 was_change_pressed/0 is_pressed/0 is_released/0 was_pressed/0 \
           was_released/0 was_released_after_hold/0 was_released_for/1 pressed_for/1 release_for/1 \
           set_debounce_thresh/1 set_hold_thresh/1 last_change/0 get_debounce_thresh/0 get_hold_thresh/0 get_update_msec/0; do
    echo "m5_btn_$b:$f"
  done
done >> "$TMP/api.txt"
sort -u "$TMP/api.txt" > m5_emu/test/atomvm_m5_api.txt
wc -l m5_emu/test/atomvm_m5_api.txt
```
Run it once and commit the output. Expected: about 145 lines.

- [ ] **Step 2: Write the failing drift test and peripheral tests**

`m5_emu/test/m5_emu_api_tests.erl`:
```erlang
-module(m5_emu_api_tests).
-include_lib("eunit/include/eunit.hrl").

every_upstream_function_is_exported_test() ->
    {ok, Bin} = file:read_file(filename:join(code:lib_dir(m5_emu), "test/atomvm_m5_api.txt")),
    Lines = [L || L <- binary:split(Bin, <<"\n">>, [global]), L =/= <<>>],
    Missing = [L || L <- Lines, not exported(L)],
    ?assertEqual([], Missing).

exported(Line) ->
    [M, FA] = binary:split(Line, <<":">>),
    [F, A] = binary:split(FA, <<"/">>),
    Mod = binary_to_atom(M, utf8),
    _ = code:ensure_loaded(Mod),
    erlang:function_exported(Mod, binary_to_atom(F, utf8), binary_to_integer(A)).
```
If `code:lib_dir(m5_emu)` does not resolve under rebar3 eunit, use `filename:join([code:priv_dir(m5_emu), "..", "test", "atomvm_m5_api.txt"])` and add an empty `m5_emu/priv/.keep`.

`m5_emu/test/m5_peripherals_tests.erl`:
```erlang
-module(m5_peripherals_tests).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    register(m5_emu_test_sink, self()),
    {ok, D} = m5_emu_display:start_link(m5_emu_bridge_test),
    {ok, I} = m5_emu_input:start_link(), {D, I}.
cleanup({D, I}) -> [begin unlink(P), exit(P, kill) end || P <- [D, I]], catch unregister(m5_emu_test_sink).
script() -> receive {script, S} -> S after 500 -> timeout end.

periph_test_() -> {foreach, fun setup/0, fun cleanup/1, [
    fun(_) -> {"tone is forwarded with volume and is_playing follows the duration", fun() ->
        ok = m5_speaker:set_volume(100),
        ok = m5_speaker:tone(2000, 50),
        ?assertEqual(<<"m5emu.exec([[\"tone\",2000,50,100]])">>, script()),
        ?assert(m5_speaker:is_playing()),
        timer:sleep(60),
        ?assertNot(m5_speaker:is_playing()) end} end,
    fun(_) -> {"stop forwards", fun() ->
        ok = m5_speaker:tone(440, 1000), _ = script(),
        ok = m5_speaker:stop(),
        ?assertEqual(<<"m5emu.exec([[\"stop_tone\"]])">>, script()),
        ?assertNot(m5_speaker:is_playing()) end} end,
    fun(_) -> {"battery level comes from the input server", fun() ->
        m5_emu_input ! {emscripten, {cast, <<"batt:55">>}}, _ = m5_emu_input:board(),
        ?assertEqual(55, m5_power:get_battery_level()),
        ?assertEqual({error, unsupported}, m5_power:deep_sleep()) end} end,
    fun(_) -> {"led pin 19 forwards, others are unsupported", fun() ->
        ok = gpio:set_pin_mode(19, output),
        ok = gpio:digital_write(19, high),
        ?assertEqual(<<"m5emu.exec([[\"led\",\"on\"]])">>, script()),
        ?assertEqual(high, gpio:digital_read(19)),
        ok = gpio:digital_write(19, 0),
        ?assertEqual(<<"m5emu.exec([[\"led\",\"off\"]])">>, script()),
        ?assertEqual({error, unsupported}, gpio:digital_write(2, high)) end} end
]}.
```

- [ ] **Step 3: Run, verify they fail**

Run: `cd m5_emu && rebar3 eunit --module=m5_emu_api_tests --module=m5_peripherals_tests`
Expected: FAIL, modules missing.

- [ ] **Step 4: Implement the peripheral modules**

Speaker and LED state live in the display server to avoid a third process. Add to `m5_emu_display`'s record: `tone_until = 0, volume = 64, led = false`, and these clauses:
```erlang
handle_call({tone, Freq, Ms}, _From, #st{volume = V} = S) ->
    Until = erlang:monotonic_time(millisecond) + Ms,
    {reply, ok, (emit({tone, Freq, Ms, V}, S))#st{tone_until = Until}};
handle_call(stop_tone, _From, S) -> {reply, ok, (emit({stop_tone}, S))#st{tone_until = 0}};
handle_call(is_playing, _From, #st{tone_until = U} = S) -> {reply, erlang:monotonic_time(millisecond) < U, S};
handle_call({set_volume, V}, _From, S) -> {reply, ok, S#st{volume = V}};
handle_call(get_volume, _From, S) -> {reply, S#st.volume, S};
handle_call({led, On}, _From, S) -> {reply, ok, (emit({led, case On of true -> on; false -> off end}, S))#st{led = On}};
handle_call(led, _From, S) -> {reply, S#st.led, S};
```
and exports `tone/2, stop_tone/0, is_playing/0, set_volume/1, get_volume/0, led/1, led/0` wrapping `gen_server:call`.

`m5_emu/src/m5_speaker.erl`:
```erlang
-module(m5_speaker).
-export([is_enabled/0, set_volume/1, get_volume/0, tone/2, tone/3, tone/4, is_playing/0, stop/0]).
is_enabled() -> true.
set_volume(V) when V >= 0, V =< 255 -> m5_emu_display:set_volume(V).
get_volume() -> m5_emu_display:get_volume().
tone(Freq, Ms) -> m5_emu_display:tone(Freq, Ms).
tone(Freq, Ms, _Channel) -> tone(Freq, Ms).
tone(Freq, Ms, _Channel, _StopCurrent) -> tone(Freq, Ms).
is_playing() -> m5_emu_display:is_playing().
stop() -> m5_emu_display:stop_tone().
```
`m5_emu/src/m5_power.erl`:
```erlang
-module(m5_power).
-export([deep_sleep/0, deep_sleep/1, deep_sleep/2, timer_sleep/1, get_battery_level/0, set_battery_charge/1,
         set_charge_current/1, set_charge_voltage/1, is_charging/0, get_type/0]).
deep_sleep() -> {error, unsupported}.  deep_sleep(_) -> {error, unsupported}.  deep_sleep(_, _) -> {error, unsupported}.
timer_sleep(_) -> {error, unsupported}.
get_battery_level() -> m5_emu_input:battery().
set_battery_charge(_) -> {error, unsupported}.  set_charge_current(_) -> {error, unsupported}.
set_charge_voltage(_) -> {error, unsupported}.
is_charging() -> false.
get_type() -> unknown.
```
`m5_emu/src/m5_rtc.erl`: export the list from `atomvm_m5_api.txt` (`is_enabled/0, get_time/0, get_date/0, get_datetime/0, set_time/1, set_date/1, set_datetime/1`); `is_enabled() -> false.`, the rest `{error, unsupported}`.
`m5_emu/src/m5_imu.erl`: `-export([is_enabled/0, get_type/0]). is_enabled() -> false. get_type() -> unknown.`
`m5_emu/src/gpio.erl`:
```erlang
-module(gpio).
-export([set_pin_mode/2, digital_write/2, digital_read/1]).
-define(LED, 19).
set_pin_mode(?LED, _Mode) -> ok;
set_pin_mode(_, _) -> {error, unsupported}.
digital_write(?LED, V) when V =:= high; V =:= 1 -> m5_emu_display:led(true);
digital_write(?LED, V) when V =:= low; V =:= 0 -> m5_emu_display:led(false);
digital_write(_, _) -> {error, unsupported}.
digital_read(?LED) -> case m5_emu_display:led() of true -> high; false -> low end;
digital_read(_) -> {error, unsupported}.
```

- [ ] **Step 5: Run the whole suite, verify it passes**

Run: `cd m5_emu && rebar3 eunit`
Expected: PASS including `every_upstream_function_is_exported_test`. If it lists missing `m5_display` functions, add them to `m5_display.erl` as `{error, unsupported}` until the list is empty.

- [ ] **Step 6: Commit**

```bash
git add m5_emu scripts/gen-atomvm-m5-api.sh
git commit -m "feat(m5_emu): speaker, power, LED shim and API drift test"
```

---

### Task 6: Pack `m5_emu.avm` and run it under the real AtomVM (node smoke test)

This task retires two risks from the spec: module shadowing across packs, and `run_script` throughput.

**Files:**
- Create: `scripts/build-m5-emu.sh`, `m5_emu/test/smoke_app/rebar.config`, `m5_emu/test/smoke_app/src/smoke_app.app.src`, `m5_emu/test/smoke_app/src/smoke_app.erl`, `m5_emu/test/node/smoke.mjs`, `m5_emu/test/node/package.json`
- Modify: `scripts/test.sh`

**Interfaces:**
- Produces `web/public/m5_emu.avm` (library pack, no start module) built by `scripts/build-m5-emu.sh`.
- Consumes `vendor/atomvm/AtomVM-node.mjs` (Task 1 fetch script).

- [ ] **Step 1: Build script for the library pack**

`scripts/build-m5-emu.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../m5_emu"
rebar3 compile
# atomvm_rebar3_plugin's packbeam task is for apps; for a library we call packbeam's escript directly
# so that no module is flagged as start module (--lib).
PACKBEAM=$(ls _build/default/plugins/atomvm_packbeam/ebin 2>/dev/null >/dev/null && echo plugin || echo none)
if [ "$PACKBEAM" = "none" ]; then rebar3 as default get-deps >/dev/null; fi
erl -noshell -pa _build/default/plugins/*/ebin -eval '
  Beams = filelib:wildcard("_build/default/lib/m5_emu/ebin/*.beam"),
  ok = packbeam_api:create("../web/public/m5_emu.avm", Beams, #{prune => false, start_module => undefined, include_lines => true}),
  halt().'
echo "wrote web/public/m5_emu.avm"
erl -noshell -pa _build/default/plugins/*/ebin -eval '
  [io:format("~s~n", [N]) || #{element_name := N} <- packbeam_api:list("../web/public/m5_emu.avm")], halt().' | head -5
```
`packbeam_api:create/3` and `packbeam_api:list/1` are the library entry points of `atomvm_packbeam` (the escript's `create --lib` calls `create` with `start_module => undefined`). If the installed `atomvm_packbeam` version names the option differently, run `rebar3 shell` and inspect `packbeam_api:module_info(exports)`; the `--lib` flag maps to a start-module-less create. Confirm the pack has no start flag with the plugin's listing: `rebar3 atomvm packbeam -l` marks start modules with `*`; our pack must show none. Add `web/public/m5_emu.avm` to `.gitignore` (it is a build artifact; the Pages workflow rebuilds it).

- [ ] **Step 2: Write the smoke app (runs under AtomVM, drives the whole stack)**

`m5_emu/test/smoke_app/rebar.config`:
```erlang
{erl_opts, [debug_info]}.
{deps, []}.
{plugins, [{atomvm_rebar3_plugin, "0.7.5"}]}.
```
`m5_emu/test/smoke_app/src/smoke_app.app.src`: `{application, smoke_app, [{description, "m5_emu smoke"}, {vsn, "0.1.0"}, {applications, [kernel, stdlib]}]}.`

`m5_emu/test/smoke_app/src/smoke_app.erl`:
```erlang
-module(smoke_app).
-export([start/0]).

start() ->
    ok = m5:begin_([]),
    io:format("SMOKE board ~p ~px~p~n", [m5:get_board(), m5_display:width(), m5_display:height()]),
    m5_display:fill_rect(10, 20, 30, 40, 16#FF0000),
    m5_display:set_cursor(0, 0),
    m5_display:println(<<"hello">>),
    %% Ask the harness to press A, then observe it through the normal polling API.
    emscripten:run_script(<<"m5emu.pressA()">>, [main_thread, async]),
    timer:sleep(30),
    m5:update(),
    io:format("SMOKE a_pressed ~p~n", [m5_btn_a:is_pressed()]),
    %% Throughput: 1000 fill_rect calls outside a batch (worst case, one run_script each).
    T0 = erlang:monotonic_time(millisecond),
    lists:foreach(fun(I) -> m5_display:fill_rect(I rem 100, 0, 1, 1, I) end, lists:seq(1, 1000)),
    T1 = erlang:monotonic_time(millisecond),
    io:format("SMOKE fill_rect_1000_ms ~p~n", [T1 - T0]),
    %% Same, batched.
    T2 = erlang:monotonic_time(millisecond),
    m5_display:start_write(),
    lists:foreach(fun(I) -> m5_display:fill_rect(I rem 100, 0, 1, 1, I) end, lists:seq(1, 1000)),
    m5_display:end_write(),
    T3 = erlang:monotonic_time(millisecond),
    io:format("SMOKE batched_1000_ms ~p~n", [T3 - T2]),
    io:format("SMOKE done~n"),
    ok.
```
Build it: `cd m5_emu/test/smoke_app && rebar3 atomvm packbeam` → `_build/default/lib/smoke_app.avm` (start module `smoke_app`).

- [ ] **Step 3: Write the node harness**

`m5_emu/test/node/package.json`: `{ "type": "module", "private": true }`.

`m5_emu/test/node/smoke.mjs`:
```js
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(import.meta.url), "../../../..");
const recorded = [];
let Module;
globalThis.m5emu = {
  exec(cmds) { recorded.push(...cmds); },
  boardReady() { Module.cast("m5_emu_input", "board:stick_cplus2:135:240"); },
  pressA() { Module.cast("m5_emu_input", "a:down"); },
};
const lines = [];
const AtomVM = (await import(resolve(root, "vendor/atomvm/AtomVM-node.mjs"))).default;
Module = await AtomVM({
  arguments: [resolve(root, "web/public/m5_emu.avm"), resolve(root, "m5_emu/test/smoke_app/_build/default/lib/smoke_app.avm")],
  print: (l) => { lines.push(l); console.log(l); },
  printErr: (l) => console.error(l),
});
// main() runs synchronously in node; by now the app has printed everything.
const get = (key) => lines.find((l) => l.startsWith(`SMOKE ${key} `))?.slice(`SMOKE ${key} `.length);
assert.equal(get("board"), "stick_cplus2 135x240", "module shadowing: m5_emu.avm must win over stubs");
assert.equal(get("a_pressed"), "true");
assert.deepEqual(recorded.find((c) => c[0] === "fill_rect"), ["fill_rect", 10, 20, 30, 40, 16711680]);
assert.ok(recorded.some((c) => c[0] === "print" && c[1] === "hello"));
const single = Number(get("fill_rect_1000_ms")), batched = Number(get("batched_1000_ms"));
console.log(`throughput: 1000 single=${single}ms batched=${batched}ms`);
assert.ok(single < 2000, `1000 unbatched fill_rect took ${single}ms (> 2000ms)`);
assert.ok(lines.includes("SMOKE done"));
console.log("smoke OK");
```
If `Module` resolves before `main` has finished (the node build may run `main` asynchronously when `arguments` are URLs), wait for `SMOKE done` by polling `lines` with a 10 s timeout before asserting.

- [ ] **Step 4: Run the smoke test, verify it passes**

Run:
```bash
mise run setup && scripts/build-m5-emu.sh && (cd m5_emu/test/smoke_app && rebar3 atomvm packbeam) && node m5_emu/test/node/smoke.mjs
```
Expected: `SMOKE board stick_cplus2 135x240`, `SMOKE a_pressed true`, a throughput line, `smoke OK`.

Troubleshooting: `SMOKE board undefined` means the start module's pack was searched first; check argument order and that `m5_emu.avm` has no start module. `nif_error` in stderr means the app's stub `m5_display.beam` won: the library pack is not first in `arguments`. If `emscripten:run_script` with `main_thread` fails on node, change `m5_emu_bridge_emscripten` to pass `[]` when `atomvm:platform()` is `emscripten` and no `window` exists; simplest is to keep `[main_thread, async]` and verify the node build accepts it (the option is a no-op without pthreads proxying).

- [ ] **Step 5: Wire into `scripts/test.sh` and commit**

Append to `scripts/test.sh`:
```bash
scripts/build-m5-emu.sh
(cd m5_emu/test/smoke_app && rebar3 atomvm packbeam)
node m5_emu/test/node/smoke.mjs
```
```bash
git add scripts m5_emu/test .gitignore
git commit -m "test(m5_emu): library pack and AtomVM node smoke test"
```

---

### Task 7: Framebuffer renderer and the 6x8 font

**Files:**
- Create: `scripts/import-font0.mjs`, `web/src/font0.ts`, `web/src/framebuffer.ts`, `web/src/renderer.ts`, `web/src/canvas.ts`
- Test: `web/test/font0.test.ts`, `web/test/renderer.test.ts`, `web/test/golden/*.png`

**Interfaces:**
- Consumes `Command` from `protocol.ts`.
- Produces:
  ```ts
  // font0.ts
  export const FONT0: Uint8Array;          // 256 glyphs * 5 column bytes, bit 0 = top row
  export const GLYPH_W = 5, CELL_W = 6, CELL_H = 8;
  // framebuffer.ts
  export class Framebuffer {
    constructor(public readonly width: number, public readonly height: number);
    fill(rgb: number): void; setPixel(x: number, y: number, rgb: number): void; getPixel(x: number, y: number): number;
    toRGBA(): Uint8ClampedArray;           // width*height*4, alpha 255
  }
  // renderer.ts
  export class M5Renderer {
    constructor(nativeWidth: number, nativeHeight: number);
    readonly fb: Framebuffer;              // always native size; rotation is applied when plotting
    rotation: number; cursor: { x: number; y: number }; textSize: { x: number; y: number };
    color: number; baseColor: number; sleeping: boolean; brightness: number;
    width(): number; height(): number;     // logical, after rotation
    exec(cmds: Command[]): void;           // applies every command; unknown names are logged once and ignored
    onEvent?: (name: string, args: (number | string)[]) => void;   // "tone", "stop_tone", "led"
  }
  // canvas.ts
  export function attachCanvas(r: M5Renderer, canvas: HTMLCanvasElement): { present(): void };
  ```

- [ ] **Step 1: Import the font table**

`scripts/import-font0.mjs` downloads `glcdfont.h` from LovyanGFX (Adafruit BSD license, keep the header) and writes `web/src/font0.ts`:
```js
import { writeFileSync } from "node:fs";
const url = "https://raw.githubusercontent.com/lovyan03/LovyanGFX/1.2.0/src/lgfx/Fonts/glcdfont.h";
const src = await (await fetch(url)).text();
const bytes = [...src.matchAll(/0x([0-9A-Fa-f]{2})/g)].map((m) => parseInt(m[1], 16));
if (bytes.length < 1280) throw new Error(`expected >= 1280 bytes, got ${bytes.length}`);
const table = bytes.slice(0, 1280);
const license = src.slice(0, src.indexOf("*/") + 2).split("\n").map((l) => "// " + l.replace(/^\/\*|\*\/$/g, "").trim()).join("\n");
writeFileSync(new URL("../web/src/font0.ts", import.meta.url),
`${license}
// Generated by scripts/import-font0.mjs from ${url}. Do not edit.
export const GLYPH_W = 5, CELL_W = 6, CELL_H = 8;
export const FONT0 = new Uint8Array([${table.join(",")}]);
`);
console.log("wrote web/src/font0.ts", table.length, "bytes");
```
Run: `node scripts/import-font0.mjs`. If tag `1.2.0` does not exist, use `master`; the table has not changed in years.

- [ ] **Step 2: Write failing tests**

`web/test/font0.test.ts`:
```ts
import { it, expect } from "vitest";
import { FONT0, GLYPH_W } from "../src/font0";
it("has 256 glyphs of 5 columns", () => expect(FONT0.length).toBe(256 * GLYPH_W));
it("glyph 'A' matches the classic 5x7 bitmap", () => {
  // Adafruit glcdfont 'A' (0x41): 0x7E 0x11 0x11 0x11 0x7E
  expect([...FONT0.slice(0x41 * 5, 0x41 * 5 + 5)]).toEqual([0x7e, 0x11, 0x11, 0x11, 0x7e]);
});
```
`web/test/renderer.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { M5Renderer } from "../src/renderer";
import { PNG } from "pngjs";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";

const mk = () => new M5Renderer(135, 240);
function expectGolden(r: M5Renderer, name: string) {
  const dir = new URL("./golden/", import.meta.url);
  mkdirSync(dir, { recursive: true });
  const file = new URL(`./golden/${name}.png`, import.meta.url);
  const png = new PNG({ width: r.fb.width, height: r.fb.height });
  png.data = Buffer.from(r.fb.toRGBA());
  const actual = PNG.sync.write(png);
  if (!existsSync(file) || process.env.UPDATE_GOLDENS) { writeFileSync(file, actual); return; }
  const expected = PNG.sync.read(readFileSync(file));
  expect(Buffer.compare(Buffer.from(expected.data), Buffer.from(png.data))).toBe(0);
}

describe("M5Renderer", () => {
  it("starts black at native size", () => {
    const r = mk();
    expect(r.width()).toBe(135); expect(r.height()).toBe(240);
    expect(r.fb.getPixel(0, 0)).toBe(0x000000);
  });
  it("fill_rect paints and clips", () => {
    const r = mk();
    r.exec([["fill_rect", 10, 20, 30, 40, 0xff0000]]);
    expect(r.fb.getPixel(10, 20)).toBe(0xff0000);
    expect(r.fb.getPixel(39, 59)).toBe(0xff0000);
    expect(r.fb.getPixel(40, 60)).toBe(0x000000);
    expect(() => r.exec([["fill_rect", -50, -50, 1000, 1000, 0x00ff00]])).not.toThrow();
    expect(r.fb.getPixel(134, 239)).toBe(0x00ff00);
    expect(() => r.exec([["draw_string", "wide text past the edge", 120, 230]])).not.toThrow();
  });
  it("rotation 1 swaps dimensions and maps coordinates", () => {
    const r = mk();
    r.exec([["set_rotation", 1], ["draw_pixel", 0, 0, 0x0000ff]]);
    expect(r.width()).toBe(240); expect(r.height()).toBe(135);
    // rotation 1 (90° clockwise): logical (0,0) is the native top-right pixel
    expect(r.fb.getPixel(134, 0)).toBe(0x0000ff);
  });
  it("draws text with the 6x8 font, white on black", () => {
    const r = mk();
    r.exec([["draw_string", "A", 0, 0]]);
    // 'A' column 0 is 0x7E: rows 1..6 set, row 0 and 7 clear
    expect(r.fb.getPixel(0, 0)).toBe(0x000000);
    expect(r.fb.getPixel(0, 1)).toBe(0xffffff);
    expect(r.fb.getPixel(0, 6)).toBe(0xffffff);
    expect(r.fb.getPixel(5, 3)).toBe(0x000000); // spacing column
    expectGolden(r, "text-A");
  });
  it("print advances the cursor and wraps", () => {
    const r = mk();
    r.exec([["set_cursor", 0, 0], ["print", "xxxxxxxxxxxxxxxxxxxxxxx"]]); // 23 x
    expect(r.cursor).toEqual({ x: 6, y: 8 });
    r.exec([["println"]]);
    expect(r.cursor).toEqual({ x: 0, y: 16 });
    r.exec([["set_text_size", 2, 2], ["print", "A"]]);
    expect(r.cursor).toEqual({ x: 12, y: 16 });
    expect(r.fb.getPixel(0, 18)).toBe(0xffffff); // scaled glyph row 1 -> y 18,19
    expectGolden(r, "print-wrap-size2");
  });
  it("sleep blanks and wakeup restores", () => {
    const r = mk();
    r.exec([["fill_screen", 0x123456], ["sleep"]]);
    expect(r.sleeping).toBe(true);
    expect(r.fb.getPixel(5, 5)).toBe(0x123456); // framebuffer kept; presentation blanks
    r.exec([["wakeup"]]);
    expect(r.sleeping).toBe(false);
  });
  it("forwards tone and led as events", () => {
    const r = mk(); const seen: any[] = [];
    r.onEvent = (n, a) => seen.push([n, ...a]);
    r.exec([["tone", 440, 100, 64], ["led", "on"], ["stop_tone"]]);
    expect(seen).toEqual([["tone", 440, 100, 64], ["led", "on"], ["stop_tone"]]);
  });
  it("shapes golden", () => {
    const r = mk();
    r.exec([["fill_screen", 0x202020], ["draw_rect", 5, 5, 50, 30, 0xffff00], ["fill_circle", 67, 120, 20, 0x00ffff],
            ["draw_circle", 67, 120, 30, 0xff00ff], ["draw_line", 0, 239, 134, 0, 0xffffff],
            ["fill_round_rect", 20, 180, 95, 40, 8, 0x4080ff], ["draw_fast_hline", 0, 100, 135, 0xff0000],
            ["draw_fast_vline", 67, 0, 240, 0x00ff00], ["fill_triangle", 10, 230, 60, 200, 110, 230, 0xffa500]]);
    expectGolden(r, "shapes");
  });
});
```
Add `pngjs` and `@types/pngjs` as dev dependencies: `cd web && pnpm add -D pngjs @types/pngjs`.

- [ ] **Step 3: Run, verify they fail**

Run: `cd web && pnpm test`
Expected: FAIL, `../src/renderer` and `../src/framebuffer` missing.

- [ ] **Step 4: Implement `framebuffer.ts`**

```ts
export class Framebuffer {
  private px: Uint32Array;
  constructor(public readonly width: number, public readonly height: number) { this.px = new Uint32Array(width * height); }
  fill(rgb: number) { this.px.fill(rgb & 0xffffff); }
  setPixel(x: number, y: number, rgb: number) {
    if (x < 0 || y < 0 || x >= this.width || y >= this.height) return;
    this.px[y * this.width + x] = rgb & 0xffffff;
  }
  getPixel(x: number, y: number): number { return this.px[y * this.width + x]; }
  toRGBA(): Uint8ClampedArray {
    const out = new Uint8ClampedArray(this.width * this.height * 4);
    for (let i = 0; i < this.px.length; i++) {
      const c = this.px[i]; out[i * 4] = c >> 16; out[i * 4 + 1] = (c >> 8) & 0xff; out[i * 4 + 2] = c & 0xff; out[i * 4 + 3] = 255;
    }
    return out;
  }
}
```

- [ ] **Step 5: Implement `renderer.ts`**

```ts
import { Framebuffer } from "./framebuffer";
import { FONT0, GLYPH_W, CELL_W, CELL_H } from "./font0";
import type { Command } from "./protocol";

const TEXT_FG = 0xffffff, TEXT_BG = 0x000000;

export class M5Renderer {
  readonly fb: Framebuffer;
  rotation = 0; cursor = { x: 0, y: 0 }; textSize = { x: 1, y: 1 };
  color = 0xffffff; baseColor = 0; sleeping = false; brightness = 128;
  onEvent?: (name: string, args: (number | string)[]) => void;
  private warned = new Set<string>();
  constructor(private nativeW: number, private nativeH: number) { this.fb = new Framebuffer(nativeW, nativeH); }

  width() { return this.rotation & 1 ? this.nativeH : this.nativeW; }
  height() { return this.rotation & 1 ? this.nativeW : this.nativeH; }

  // Logical -> native, M5GFX rotation convention (clockwise quarter turns).
  private plot(x: number, y: number, c: number) {
    const W = this.nativeW, H = this.nativeH;
    switch (this.rotation & 3) {
      case 0: this.fb.setPixel(x, y, c); break;
      case 1: this.fb.setPixel(W - 1 - y, x, c); break;
      case 2: this.fb.setPixel(W - 1 - x, H - 1 - y, c); break;
      case 3: this.fb.setPixel(y, H - 1 - x, c); break;
    }
  }
  private fillRect(x: number, y: number, w: number, h: number, c: number) {
    const x0 = Math.max(0, x), y0 = Math.max(0, y), x1 = Math.min(this.width(), x + w), y1 = Math.min(this.height(), y + h);
    for (let yy = y0; yy < y1; yy++) for (let xx = x0; xx < x1; xx++) this.plot(xx, yy, c);
  }
  private drawRect(x: number, y: number, w: number, h: number, c: number) {
    this.fillRect(x, y, w, 1, c); this.fillRect(x, y + h - 1, w, 1, c); this.fillRect(x, y, 1, h, c); this.fillRect(x + w - 1, y, 1, h, c);
  }
  private line(x0: number, y0: number, x1: number, y1: number, c: number) { // Bresenham
    let dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx + dy;
    for (;;) { this.plot(x0, y0, c); if (x0 === x1 && y0 === y1) break; const e2 = 2 * err; if (e2 >= dy) { err += dy; x0 += sx; } if (e2 <= dx) { err += dx; y0 += sy; } }
  }
  private circle(cx: number, cy: number, r: number, c: number, fill: boolean) {
    for (let y = -r; y <= r; y++) {
      const half = Math.round(Math.sqrt(r * r - y * y));
      if (fill) this.fillRect(cx - half, cy + y, 2 * half + 1, 1, c);
      else { this.plot(cx - half, cy + y, c); this.plot(cx + half, cy + y, c); }
    }
    if (!fill) for (let x = -r; x <= r; x++) { const half = Math.round(Math.sqrt(r * r - x * x)); this.plot(cx + x, cy - half, c); this.plot(cx + x, cy + half, c); }
  }
  private ellipse(cx: number, cy: number, rx: number, ry: number, c: number, fill: boolean) {
    for (let y = -ry; y <= ry; y++) {
      const half = Math.round(rx * Math.sqrt(1 - (y * y) / (ry * ry)));
      if (fill) this.fillRect(cx - half, cy + y, 2 * half + 1, 1, c); else { this.plot(cx - half, cy + y, c); this.plot(cx + half, cy + y, c); }
    }
  }
  private roundRect(x: number, y: number, w: number, h: number, r: number, c: number, fill: boolean) {
    r = Math.min(r, Math.floor(w / 2), Math.floor(h / 2));
    if (fill) {
      this.fillRect(x + r, y, w - 2 * r, h, c);
      for (let yy = 0; yy < r; yy++) {
        const half = Math.round(Math.sqrt(r * r - (r - yy) * (r - yy)));
        this.fillRect(x + r - half, y + yy, half, 1, c); this.fillRect(x + w - r, y + yy, half, 1, c);
        this.fillRect(x + r - half, y + h - 1 - yy, half, 1, c); this.fillRect(x + w - r, y + h - 1 - yy, half, 1, c);
      }
      this.fillRect(x, y + r, r, h - 2 * r, c); this.fillRect(x + w - r, y + r, r, h - 2 * r, c);
    } else {
      this.fillRect(x + r, y, w - 2 * r, 1, c); this.fillRect(x + r, y + h - 1, w - 2 * r, 1, c);
      this.fillRect(x, y + r, 1, h - 2 * r, c); this.fillRect(x + w - 1, y + r, 1, h - 2 * r, c);
      for (let yy = 0; yy < r; yy++) {
        const half = Math.round(Math.sqrt(r * r - (r - yy) * (r - yy)));
        this.plot(x + r - half, y + yy, c); this.plot(x + w - 1 - r + half, y + yy, c);
        this.plot(x + r - half, y + h - 1 - yy, c); this.plot(x + w - 1 - r + half, y + h - 1 - yy, c);
      }
    }
  }
  private triangle(x0: number, y0: number, x1: number, y1: number, x2: number, y2: number, c: number, fill: boolean) {
    if (!fill) { this.line(x0, y0, x1, y1, c); this.line(x1, y1, x2, y2, c); this.line(x2, y2, x0, y0, c); return; }
    const ys = Math.min(y0, y1, y2), ye = Math.max(y0, y1, y2);
    for (let y = ys; y <= ye; y++) {
      const xs: number[] = [];
      for (const [ax, ay, bx, by] of [[x0, y0, x1, y1], [x1, y1, x2, y2], [x2, y2, x0, y0]]) {
        if ((y >= ay && y < by) || (y >= by && y < ay)) xs.push(ax + ((y - ay) * (bx - ax)) / (by - ay));
      }
      if (xs.length >= 2) { const a = Math.round(Math.min(...xs)), b = Math.round(Math.max(...xs)); this.fillRect(a, y, b - a + 1, 1, c); }
    }
  }
  private glyph(ch: number, x: number, y: number) {
    const { x: sx, y: sy } = this.textSize;
    for (let col = 0; col < CELL_W; col++) {
      const bits = col < GLYPH_W ? FONT0[(ch & 0xff) * GLYPH_W + col] : 0;
      for (let row = 0; row < CELL_H; row++) {
        const on = row < 7 && ((bits >> row) & 1) === 1;
        this.fillRect(x + col * sx, y + row * sy, sx, sy, on ? TEXT_FG : TEXT_BG);
      }
    }
  }
  private drawString(s: string, x: number, y: number) {
    const cw = CELL_W * this.textSize.x;
    for (let i = 0; i < s.length; i++) this.glyph(s.charCodeAt(i), x + i * cw, y);
  }
  private print(s: string) {
    const cw = CELL_W * this.textSize.x, ch = CELL_H * this.textSize.y, W = this.width();
    for (const c of s) {
      if (c === "\n") { this.cursor = { x: 0, y: this.cursor.y + ch }; continue; }
      if (c === "\r") { this.cursor.x = 0; continue; }
      if (this.cursor.x + cw > W) this.cursor = { x: 0, y: this.cursor.y + ch };
      this.glyph(c.charCodeAt(0), this.cursor.x, this.cursor.y);
      this.cursor = { x: this.cursor.x + cw, y: this.cursor.y };
    }
  }

  exec(cmds: Command[]) {
    for (const [name, ...a] of cmds) {
      const n = a as number[];
      switch (name) {
        case "fill_screen": this.fillRect(0, 0, this.width(), this.height(), n[0]); break;
        case "fill_rect": this.fillRect(n[0], n[1], n[2], n[3], n[4]); break;
        case "draw_rect": this.drawRect(n[0], n[1], n[2], n[3], n[4]); break;
        case "draw_pixel": this.plot(n[0], n[1], n[2]); break;
        case "draw_fast_vline": this.fillRect(n[0], n[1], 1, n[2], n[3]); break;
        case "draw_fast_hline": this.fillRect(n[0], n[1], n[2], 1, n[3]); break;
        case "draw_line": this.line(n[0], n[1], n[2], n[3], n[4]); break;
        case "draw_circle": this.circle(n[0], n[1], n[2], n[3], false); break;
        case "fill_circle": this.circle(n[0], n[1], n[2], n[3], true); break;
        case "draw_ellipse": this.ellipse(n[0], n[1], n[2], n[3], n[4], false); break;
        case "fill_ellipse": this.ellipse(n[0], n[1], n[2], n[3], n[4], true); break;
        case "draw_round_rect": this.roundRect(n[0], n[1], n[2], n[3], n[4], n[5], false); break;
        case "fill_round_rect": this.roundRect(n[0], n[1], n[2], n[3], n[4], n[5], true); break;
        case "draw_triangle": this.triangle(n[0], n[1], n[2], n[3], n[4], n[5], n[6], false); break;
        case "fill_triangle": this.triangle(n[0], n[1], n[2], n[3], n[4], n[5], n[6], true); break;
        case "draw_string": this.drawString(String(a[0]), n[1], n[2]); break;
        case "draw_center_string": { const s = String(a[0]); this.drawString(s, n[1] - Math.floor((s.length * CELL_W * this.textSize.x) / 2), n[2]); break; }
        case "draw_right_string": { const s = String(a[0]); this.drawString(s, n[1] - s.length * CELL_W * this.textSize.x, n[2]); break; }
        case "print": this.print(String(a[0])); break;
        case "println": this.print("\n"); break;
        case "set_cursor": this.cursor = { x: n[0], y: n[1] }; break;
        case "set_text_size": this.textSize = { x: Math.max(1, Math.round(n[0])), y: Math.max(1, Math.round(n[1])) }; break;
        case "set_color": this.color = n[0]; break;
        case "set_base_color": this.baseColor = n[0]; break;
        case "set_rotation": this.rotation = n[0] & 3; break;
        case "set_brightness": this.brightness = n[0]; break;
        case "sleep": this.sleeping = true; break;
        case "wakeup": this.sleeping = false; break;
        case "tone": case "stop_tone": case "led": this.onEvent?.(name, a); break;
        default:
          if (!this.warned.has(name)) { this.warned.add(name); console.warn(`m5emu: unsupported command ${name}`); }
      }
    }
  }
}
```
Text size in the Erlang side is sent as given (`set_text_size(2)` → `[2,2]`); M5GFX accepts fractional sizes, but the renderer rounds to whole pixels, which is what the StickC shows for integer sizes.

- [ ] **Step 6: Implement `canvas.ts`**

```ts
import type { M5Renderer } from "./renderer";
export function attachCanvas(r: M5Renderer, canvas: HTMLCanvasElement) {
  const ctx = canvas.getContext("2d")!;
  let image = ctx.createImageData(r.fb.width, r.fb.height);
  return {
    present() {
      if (canvas.width !== r.fb.width || canvas.height !== r.fb.height) {
        canvas.width = r.fb.width; canvas.height = r.fb.height; image = ctx.createImageData(r.fb.width, r.fb.height);
      }
      image.data.set(r.fb.toRGBA());
      ctx.putImageData(image, 0, 0);
      canvas.style.opacity = r.sleeping ? "0" : String(0.25 + 0.75 * (r.brightness / 255));
    },
  };
}
```
The canvas is sized natively (135x240) and scaled with CSS (`width: 405px; image-rendering: pixelated`), so rotation never changes the element.

- [ ] **Step 7: Run tests, verify they pass; inspect goldens**

Run: `cd web && pnpm test`
Expected: PASS; first run writes `web/test/golden/{text-A,print-wrap-size2,shapes}.png`. Open them and check by eye: an "A", 23 x's wrapping with a large A below, and the shapes. Commit the PNGs. Re-running must pass without `UPDATE_GOLDENS`.

- [ ] **Step 8: Commit**

```bash
git add scripts/import-font0.mjs web/src web/test web/package.json web/pnpm-lock.yaml
git commit -m "feat(web): framebuffer renderer with M5GFX semantics and 6x8 font"
```

---

### Task 8: VM glue, app loader, inputs, audio, console and the page

**Files:**
- Create: `web/src/vm.ts`, `web/src/loader.ts`, `web/src/input.ts`, `web/src/audio.ts`, `web/src/console.ts`, `web/src/main.ts` (replace), `web/index.html` (replace), `web/src/style.css`, `web/public/coi-serviceworker.js`
- Test: `web/test/vm.test.ts`, `web/test/loader.test.ts`, `web/test/input.test.ts`

**Interfaces:**
- Consumes `loadBoardProfile`, `boardMessage`, `buttonMessage`, `batteryMessage`, `INPUT_PROCESS`, `M5Renderer`, `attachCanvas`.
- Produces:
  ```ts
  // vm.ts
  export interface VmFactory { (opts: Record<string, unknown>): Promise<{ cast(name: string, msg: string): void }> }
  export interface VmHandle { cast(name: string, msg: string): void; exited: Promise<number> }
  export async function startVm(o: {
    factory: VmFactory;                   // default: import of `${base}atomvm/AtomVM.mjs`
    avmUrls: string[];                    // library first, app second
    onStdout(line: string): void; onStderr(line: string): void;
  }): Promise<VmHandle>
  // loader.ts
  export interface LoadedApp { name: string; bytes: Uint8Array }
  export async function appFromFile(f: File): Promise<LoadedApp>
  export async function appFromUrl(url: string): Promise<LoadedApp>
  export function appUrl(app: LoadedApp): string                // blob: URL for the VM to fetch
  export async function saveLastApp(app: LoadedApp): Promise<void>
  export async function loadLastApp(): Promise<LoadedApp | undefined>
  // input.ts
  export function bindInputs(profile: BoardProfile, root: HTMLElement, cast: (msg: string) => void): () => void  // returns unbind
  // audio.ts
  export class Buzzer { tone(freqHz: number, ms: number, volume0to255: number): void; stop(): void }
  // console.ts
  export function makeConsole(el: HTMLElement): { out(line: string): void; err(line: string): void; clear(): void }
  ```

- [ ] **Step 1: Write failing tests**

`web/test/vm.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { startVm } from "../src/vm";

function fakeFactory(script: (m: any) => void) {
  return async (opts: any) => {
    const m = { cast: (_n: string, _s: string) => {}, opts };
    queueMicrotask(() => script({ ...m, print: opts.print, printErr: opts.printErr, onExit: opts.onExit }));
    return m;
  };
}
describe("startVm", () => {
  it("passes library then app and relays stdout", async () => {
    const out: string[] = [];
    const vm = await startVm({
      factory: fakeFactory((m) => { m.print("hello"); m.onExit(0); }),
      avmUrls: ["/m5_emu.avm", "blob:app"], onStdout: (l) => out.push(l), onStderr: () => {},
    });
    expect(await vm.exited).toBe(0);
    expect(out).toEqual(["hello"]);
  });
  it("exit with error surfaces stderr", async () => {
    const err: string[] = [];
    const vm = await startVm({
      factory: fakeFactory((m) => { m.printErr("Cannot load startup module: boom"); m.onExit(1); }),
      avmUrls: ["/m5_emu.avm", "blob:app"], onStdout: () => {}, onStderr: (l) => err.push(l),
    });
    expect(await vm.exited).toBe(1);
    expect(err[0]).toMatch(/startup module/);
  });
  it("sends the arguments in order", async () => {
    let seen: string[] = [];
    await startVm({ factory: async (o: any) => { seen = o.arguments; return { cast() {} }; },
      avmUrls: ["/m5_emu.avm", "blob:app"], onStdout() {}, onStderr() {} });
    expect(seen).toEqual(["/m5_emu.avm", "blob:app"]);
  });
});
```
`web/test/loader.test.ts` (uses `fake-indexeddb`; `pnpm add -D fake-indexeddb idb-keyval`):
```ts
import "fake-indexeddb/auto";
import { describe, it, expect } from "vitest";
import { appFromFile, saveLastApp, loadLastApp } from "../src/loader";
describe("loader", () => {
  it("reads a dropped file", async () => {
    const f = new File([new Uint8Array([1, 2, 3])], "clock.avm");
    const app = await appFromFile(f);
    expect(app.name).toBe("clock.avm"); expect([...app.bytes]).toEqual([1, 2, 3]);
  });
  it("rejects non-avm files", async () => {
    await expect(appFromFile(new File([""], "x.beam"))).rejects.toThrow(/\.avm/);
  });
  it("replace app: the last saved app wins", async () => {
    await saveLastApp({ name: "a.avm", bytes: new Uint8Array([1]) });
    await saveLastApp({ name: "b.avm", bytes: new Uint8Array([2]) });
    const last = await loadLastApp();
    expect(last?.name).toBe("b.avm"); expect([...last!.bytes]).toEqual([2]);
  });
});
```
`web/test/input.test.ts` (vitest `environment: "jsdom"` for this file via a `// @vitest-environment jsdom` header; `pnpm add -D jsdom`):
```ts
// @vitest-environment jsdom
import { describe, it, expect } from "vitest";
import { bindInputs } from "../src/input";
import { parseBoardProfile } from "../src/board";
import { readFileSync } from "node:fs";
const p = parseBoardProfile(JSON.parse(readFileSync(new URL("../../boards/m5stickc_plus2/board.json", import.meta.url), "utf8")));
describe("bindInputs", () => {
  it("renders a button per profile entry and casts down/up", () => {
    const root = document.createElement("div"); const sent: string[] = [];
    bindInputs(p, root, (m) => sent.push(m));
    const a = root.querySelector<HTMLButtonElement>('[data-btn="a"]')!;
    expect(root.querySelectorAll("[data-btn]").length).toBe(3);
    a.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true }));
    a.dispatchEvent(new MouseEvent("pointerup", { bubbles: true }));
    expect(sent).toEqual(["a:down", "a:up"]);
  });
  it("maps keyboard shortcuts and ignores repeats", () => {
    const root = document.createElement("div"); const sent: string[] = [];
    document.body.appendChild(root);
    bindInputs(p, root, (m) => sent.push(m));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "p" }));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "p", repeat: true }));
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "p" }));
    expect(sent).toEqual(["pwr:down", "pwr:up"]);
  });
  it("battery slider casts batt:N", () => {
    const root = document.createElement("div"); const sent: string[] = [];
    bindInputs(p, root, (m) => sent.push(m));
    const s = root.querySelector<HTMLInputElement>('input[type="range"]')!;
    s.value = "37"; s.dispatchEvent(new Event("input", { bubbles: true }));
    expect(sent).toEqual(["batt:37"]);
  });
});
```

- [ ] **Step 2: Run, verify they fail**

Run: `cd web && pnpm test`
Expected: FAIL on the three new files (modules missing).

- [ ] **Step 3: Implement `vm.ts`**

```ts
export interface VmFactory { (opts: Record<string, unknown>): Promise<{ cast(name: string, msg: string): void }> }
export interface VmHandle { cast(name: string, msg: string): void; exited: Promise<number> }

export async function defaultFactory(): Promise<VmFactory> {
  const base = import.meta.env.BASE_URL;
  const mod = await import(/* @vite-ignore */ new URL(`${base}atomvm/AtomVM.mjs`, location.href).href);
  return mod.default as VmFactory;
}

export async function startVm(o: { factory: VmFactory; avmUrls: string[]; onStdout(l: string): void; onStderr(l: string): void }): Promise<VmHandle> {
  let resolveExit!: (code: number) => void;
  const exited = new Promise<number>((r) => (resolveExit = r));
  const module = await o.factory({
    arguments: o.avmUrls,
    print: o.onStdout,
    printErr: o.onStderr,
    onExit: (code: number) => resolveExit(code),
    noExitRuntime: false,
  });
  return { cast: (n, m) => module.cast(n, m), exited };
}
```
Emscripten calls `onExit` when `main` returns; with `PROXY_TO_PTHREAD` that happens on the worker and is forwarded to the module on the main thread.

- [ ] **Step 4: Implement `loader.ts`, `input.ts`, `audio.ts`, `console.ts`**

`web/src/loader.ts`:
```ts
import { get, set } from "idb-keyval";
export interface LoadedApp { name: string; bytes: Uint8Array }
const KEY = "atomvm_watch.lastApp";
export async function appFromFile(f: File): Promise<LoadedApp> {
  if (!f.name.endsWith(".avm")) throw new Error(`expected a .avm file, got ${f.name}`);
  return { name: f.name, bytes: new Uint8Array(await f.arrayBuffer()) };
}
export async function appFromUrl(url: string): Promise<LoadedApp> {
  const res = await fetch(url); if (!res.ok) throw new Error(`fetch ${url}: ${res.status}`);
  return { name: url.split("/").pop() || "app.avm", bytes: new Uint8Array(await res.arrayBuffer()) };
}
export function appUrl(app: LoadedApp): string {
  // The VM fetches arguments by URL; a blob URL keeps the ".avm" suffix check happy via a hash fragment-free path,
  // so append the name as a search param the VM ignores but strrchr('.') sees.
  const blob = new Blob([app.bytes], { type: "application/octet-stream" });
  return URL.createObjectURL(blob) + "#/" + app.name;
}
export const saveLastApp = (app: LoadedApp) => set(KEY, app);
export const loadLastApp = () => get<LoadedApp>(KEY);
```
Important: AtomVM's `load_module` decides `.avm` vs `.beam` with `strrchr(path, '.')` on the whole string, so the URL passed to the VM must end in `.avm`. A blob URL is `blob:https://host/uuid`; appending `#/clock.avm` keeps the fetch target the same (fragments are not sent) while the suffix check passes. If `emscripten_fetch` rejects fragments, fall back to a service-worker route: register `/__app/<name>` in `coi-serviceworker`'s scope with a `fetch` handler that answers from a `Cache` entry the page writes with `caches.open("apps")`. Decide by the e2e test in Task 11.

`web/src/input.ts`:
```ts
import type { BoardProfile } from "./board";
import { buttonMessage, batteryMessage } from "./protocol";
export function bindInputs(profile: BoardProfile, root: HTMLElement, cast: (msg: string) => void): () => void {
  const held = new Set<string>();
  const down = (id: string) => { if (held.has(id)) return; held.add(id); cast(buttonMessage(id, true)); };
  const up = (id: string) => { if (!held.has(id)) return; held.delete(id); cast(buttonMessage(id, false)); };
  const bar = document.createElement("div"); bar.className = "buttons";
  for (const b of profile.buttons) {
    const el = document.createElement("button"); el.dataset.btn = b.id; el.textContent = `${b.label} (${b.key})`;
    el.addEventListener("pointerdown", () => down(b.id));
    el.addEventListener("pointerup", () => up(b.id));
    el.addEventListener("pointerleave", () => up(b.id));
    bar.appendChild(el);
  }
  root.appendChild(bar);
  if (profile.peripherals.battery) {
    const s = document.createElement("input"); s.type = "range"; s.min = "0"; s.max = "100"; s.value = "100"; s.title = "Battery";
    s.addEventListener("input", () => cast(batteryMessage(Number(s.value))));
    root.appendChild(s);
  }
  const byKey = new Map(profile.buttons.map((b) => [b.key, b.id]));
  const kd = (e: KeyboardEvent) => { if (e.repeat) return; const id = byKey.get(e.key.toLowerCase()); if (id) { e.preventDefault(); down(id); } };
  const ku = (e: KeyboardEvent) => { const id = byKey.get(e.key.toLowerCase()); if (id) up(id); };
  window.addEventListener("keydown", kd); window.addEventListener("keyup", ku);
  return () => { window.removeEventListener("keydown", kd); window.removeEventListener("keyup", ku); bar.remove(); };
}
```
`web/src/audio.ts`:
```ts
export class Buzzer {
  private ctx?: AudioContext; private osc?: OscillatorNode; private gain?: GainNode; private timer?: number;
  tone(freq: number, ms: number, volume: number) {
    this.stop();
    this.ctx ??= new AudioContext();
    this.osc = this.ctx.createOscillator(); this.gain = this.ctx.createGain();
    this.osc.type = "square"; this.osc.frequency.value = freq; this.gain.gain.value = 0.2 * (volume / 255);
    this.osc.connect(this.gain).connect(this.ctx.destination); this.osc.start();
    this.timer = window.setTimeout(() => this.stop(), ms);
  }
  stop() { if (this.timer) clearTimeout(this.timer); this.osc?.stop(); this.osc?.disconnect(); this.osc = undefined; }
}
```
`web/src/console.ts`:
```ts
export function makeConsole(el: HTMLElement) {
  const add = (line: string, cls: string) => { const d = document.createElement("div"); d.className = cls; d.textContent = line; el.appendChild(d); el.scrollTop = el.scrollHeight; };
  return { out: (l: string) => add(l, "out"), err: (l: string) => add(l, "err"), clear: () => (el.textContent = "") };
}
```

- [ ] **Step 5: Page and wiring**

`web/index.html`:
```html
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>atomvm_watch</title><script src="./coi-serviceworker.js"></script><link rel="stylesheet" href="/src/style.css"></head>
<body>
<header><h1>atomvm_watch</h1><span id="board-name"></span></header>
<main>
  <section class="device"><div class="frame"><canvas id="screen"></canvas><div id="led" class="led"></div></div><div id="controls"></div></section>
  <section class="side">
    <div id="drop" class="drop">Drop an <code>.avm</code> here, or <label><input id="file" type="file" accept=".avm" hidden>choose a file</label></div>
    <div id="app-name"></div>
    <div class="row"><button id="restart" hidden>Restart</button></div>
    <details id="install"><summary>Install to device</summary>
      <button id="connect">Connect (Web Serial)</button><span id="chip"></span>
      <button id="install-runtime" disabled>Install runtime</button>
      <button id="install-app" disabled>Install app</button>
      <progress id="progress" max="100" value="0" hidden></progress>
    </details>
    <pre id="console" class="console"></pre>
  </section>
</main>
<script type="module" src="/src/main.ts"></script>
</body></html>
```
Copy `node_modules/coi-serviceworker/coi-serviceworker.js` to `web/public/` (`pnpm add -D coi-serviceworker`; add a `postinstall` script: `cp node_modules/coi-serviceworker/coi-serviceworker.js public/`).

`web/src/main.ts`:
```ts
import { loadBoardProfile } from "./board";
import { boardMessage, INPUT_PROCESS, type Command } from "./protocol";
import { M5Renderer } from "./renderer";
import { attachCanvas } from "./canvas";
import { startVm, defaultFactory, type VmHandle } from "./vm";
import { appFromFile, appFromUrl, appUrl, saveLastApp, loadLastApp, type LoadedApp } from "./loader";
import { bindInputs } from "./input";
import { Buzzer } from "./audio";
import { makeConsole } from "./console";
import { setupInstaller } from "./installer";

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const params = new URLSearchParams(location.search);
const profile = await loadBoardProfile(params.get("board") ?? "m5stickc_plus2");
$("board-name").textContent = profile.name;
const con = makeConsole($("console"));
const renderer = new M5Renderer(profile.screen.width, profile.screen.height);
const canvas = $<HTMLCanvasElement>("screen"); canvas.style.width = `${profile.screen.width * profile.screen.scale}px`;
const view = attachCanvas(renderer, canvas);
const buzzer = new Buzzer();
renderer.onEvent = (n, a) => { if (n === "tone") buzzer.tone(+a[0], +a[1], +a[2]); else if (n === "stop_tone") buzzer.stop(); else if (n === "led") $("led").classList.toggle("on", a[0] === "on"); };
let dirty = false;
(window as any).m5emu = {
  exec(cmds: Command[]) { renderer.exec(cmds); dirty = true; },
  boardReady() { vm?.cast(INPUT_PROCESS, boardMessage(profile)); },
};
requestAnimationFrame(function tick() { if (dirty) { view.present(); dirty = false; } requestAnimationFrame(tick); });

let vm: VmHandle | undefined; let current: LoadedApp | undefined;
bindInputs(profile, $("controls"), (m) => vm?.cast(INPUT_PROCESS, m));

async function run(app: LoadedApp) {
  if (vm) { location.reload(); return; }           // a wasm pthread module cannot be torn down cleanly; reload with the app saved
  current = app; $("app-name").textContent = app.name; con.clear();
  await saveLastApp(app);
  vm = await startVm({ factory: await defaultFactory(), avmUrls: [`${import.meta.env.BASE_URL}m5_emu.avm`, appUrl(app)], onStdout: con.out, onStderr: con.err });
  vm.exited.then((code) => { con.err(`VM exited with code ${code}`); $("restart").hidden = false; });
}
$("restart").onclick = () => location.reload();
$<HTMLInputElement>("file").onchange = async (e) => { const f = (e.target as HTMLInputElement).files?.[0]; if (f) run(await appFromFile(f)); };
const drop = $("drop");
drop.ondragover = (e) => { e.preventDefault(); drop.classList.add("over"); };
drop.ondragleave = () => drop.classList.remove("over");
drop.ondrop = async (e) => { e.preventDefault(); drop.classList.remove("over"); const f = e.dataTransfer?.files[0]; if (f) run(await appFromFile(f)); };
setupInstaller(profile, { connect: $("connect"), runtime: $("install-runtime"), app: $("install-app"), chip: $("chip"), progress: $<HTMLProgressElement>("progress") }, () => current, con);

const avmParam = params.get("avm");
if (avmParam) run(await appFromUrl(avmParam));
else { const last = await loadLastApp(); if (last) run(last); }
```
`setupInstaller` is defined in Task 9; until then export a stub `export function setupInstaller() {}` from `web/src/installer.ts` so the page builds.

`web/src/style.css`: dark theme, `.frame` positioned relative with the device SVG as background (`url(./boards/m5stickc_plus2/device.svg)`), `canvas { image-rendering: pixelated; position: absolute; left: 32px*scale/… }`. Keep it simple: a flex layout with the device on the left and the side panel on the right, `.console { height: 14rem; overflow: auto; background: #111; color: #ddd; font: 12px monospace }`, `.led.on { background: #f00; box-shadow: 0 0 8px #f00 }`.

- [ ] **Step 6: Run tests and the dev server**

Run: `cd web && pnpm test && pnpm build`
Expected: all vitest files PASS; `vite build` succeeds.
Manual: `cd web && pnpm dev`, open `http://localhost:5173/?avm=http://localhost:5173/fixtures/smoke_app.avm` after copying `m5_emu/test/smoke_app/_build/default/lib/smoke_app.avm` to `web/public/fixtures/`. Expected: console shows `SMOKE board stick_cplus2 135x240`, a red rectangle and "hello" on the canvas. If the console shows `Failed opening blob:...`, apply the service-worker fallback described in `loader.ts`.

- [ ] **Step 7: Commit**

```bash
git add web
git commit -m "feat(web): VM glue, app loader, inputs, buzzer, console and page"
```

---

### Task 9: Web Serial installer

**Files:**
- Create: `web/src/installer.ts` (replace stub), `web/src/flash.ts`
- Test: `web/test/flash.test.ts`, `web/test/installer.test.ts`

**Interfaces:**
- Produces:
  ```ts
  // flash.ts — pure logic, no Web Serial
  export interface FirmwareManifest { version: string; chip: string; atomvm: string; parts: { path: string; offset: number }[]; appOffset: number }
  export function parseManifest(json: unknown): FirmwareManifest       // throws on missing fields
  export function toBinaryString(bytes: Uint8Array): string            // esptool-js wants binary strings
  export function checkChip(expected: string, reported: string): void  // throws unless reported starts with expected and has no suffix like "-S3"
  // installer.ts
  export interface Flasher { connect(): Promise<string>; write(parts: { data: Uint8Array; address: number }[], onProgress: (pct: number) => void): Promise<void>; reset(): Promise<void> }
  export function esptoolFlasher(): Flasher                            // real one, uses navigator.serial + esptool-js
  export function setupInstaller(profile: BoardProfile, els: {...}, currentApp: () => LoadedApp | undefined, con: Console, flasher?: Flasher): void
  ```

- [ ] **Step 1: Write failing tests**

`web/test/flash.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { parseManifest, toBinaryString, checkChip } from "../src/flash";
describe("flash helpers", () => {
  it("parses a manifest", () => {
    const m = parseManifest({ version: "0.1.0", chip: "ESP32", atomvm: "v0.7.0-beta.0", parts: [{ path: "AtomVM-m5stickc_plus2-0.1.0.img", offset: 4096 }], appOffset: 2424832 });
    expect(m.parts[0].offset).toBe(0x1000); expect(m.appOffset).toBe(0x250000);
  });
  it("rejects a manifest without parts", () => { expect(() => parseManifest({ version: "1", chip: "ESP32" })).toThrow(/parts/); });
  it("converts bytes to a binary string", () => { expect(toBinaryString(new Uint8Array([0, 65, 255]))).toBe("\u0000Aÿ"); });
  it("wrong chip refuses", () => {
    expect(() => checkChip("ESP32", "ESP32-S3")).toThrow(/ESP32-S3/);
    expect(() => checkChip("ESP32", "ESP32-C3")).toThrow();
    expect(() => checkChip("ESP32", "ESP32-D0WD-V3 (revision v3.1)")).not.toThrow();
    expect(() => checkChip("ESP32", "ESP32-PICO-V3-02")).not.toThrow();
  });
});
```
`web/test/installer.test.ts` (`// @vitest-environment jsdom`):
```ts
// @vitest-environment jsdom
import { describe, it, expect, vi } from "vitest";
import { setupInstaller, type Flasher } from "../src/installer";
import { parseBoardProfile } from "../src/board";
import { readFileSync } from "node:fs";
const p = parseBoardProfile(JSON.parse(readFileSync(new URL("../../boards/m5stickc_plus2/board.json", import.meta.url), "utf8")));
function els() {
  const mk = (tag: string) => document.createElement(tag);
  return { connect: mk("button"), runtime: mk("button") as HTMLButtonElement, app: mk("button") as HTMLButtonElement, chip: mk("span"), progress: mk("progress") as HTMLProgressElement };
}
const con = { out: vi.fn(), err: vi.fn(), clear: vi.fn() };
describe("setupInstaller", () => {
  it("writes the current app at the profile offset", async () => {
    const writes: any[] = [];
    const flasher: Flasher = { connect: async () => "ESP32-PICO-V3-02", write: async (parts) => { writes.push(...parts); }, reset: async () => {} };
    const e = els(); const app = { name: "clock.avm", bytes: new Uint8Array([9, 9]) };
    setupInstaller(p, e, () => app, con, flasher);
    e.connect.click(); await new Promise((r) => setTimeout(r, 0));
    expect(e.app.disabled).toBe(false);
    e.app.click(); await new Promise((r) => setTimeout(r, 0));
    expect(writes).toEqual([{ data: app.bytes, address: 0x250000 }]);
  });
  it("wrong chip refuses and keeps buttons disabled", async () => {
    const flasher: Flasher = { connect: async () => "ESP32-S3", write: vi.fn(async () => {}), reset: async () => {} };
    const e = els();
    setupInstaller(p, e, () => undefined, con, flasher);
    e.connect.click(); await new Promise((r) => setTimeout(r, 0));
    expect(e.app.disabled).toBe(true); expect(e.runtime.disabled).toBe(true);
    expect(con.err).toHaveBeenCalledWith(expect.stringMatching(/ESP32-S3/));
  });
});
```

- [ ] **Step 2: Run, verify they fail**

Run: `cd web && pnpm test`
Expected: FAIL, `flash.ts` missing, `setupInstaller` stub has the wrong signature.

- [ ] **Step 3: Implement `flash.ts`**

```ts
export interface FirmwareManifest { version: string; chip: string; atomvm: string; parts: { path: string; offset: number }[]; appOffset: number }
export function parseManifest(json: unknown): FirmwareManifest {
  const m = json as Partial<FirmwareManifest>;
  for (const k of ["version", "chip", "atomvm", "parts", "appOffset"] as const) if (m[k] === undefined) throw new Error(`manifest missing ${k}`);
  if (!Array.isArray(m.parts) || m.parts.length === 0) throw new Error("manifest parts must be a non-empty array");
  return m as FirmwareManifest;
}
export function toBinaryString(bytes: Uint8Array): string {
  let s = ""; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return s;
}
export function checkChip(expected: string, reported: string): void {
  // esptool reports e.g. "ESP32-D0WD-V3 (revision v3.1)", "ESP32-PICO-V3-02", "ESP32-S3", "ESP32-C3".
  const family = reported.split(/[\s(]/)[0];                       // "ESP32-PICO-V3-02"
  const bad = /^ESP32-(S|C|H|P)\d/i.test(family);
  if (bad || !family.toUpperCase().startsWith(expected.toUpperCase())) throw new Error(`connected chip is ${reported}, this board needs ${expected}`);
}
```

- [ ] **Step 4: Implement `installer.ts`**

```ts
import { ESPLoader, Transport } from "esptool-js";
import type { BoardProfile } from "./board";
import type { LoadedApp } from "./loader";
import { parseManifest, toBinaryString, checkChip } from "./flash";

export interface Flasher {
  connect(): Promise<string>;
  write(parts: { data: Uint8Array; address: number }[], onProgress: (pct: number) => void): Promise<void>;
  reset(): Promise<void>;
}
type Console = { out(l: string): void; err(l: string): void };

export function esptoolFlasher(log: Console): Flasher {
  let loader: ESPLoader | undefined;
  return {
    async connect() {
      if (!("serial" in navigator)) throw new Error("Web Serial is not available; use Chrome or Edge over HTTPS or localhost");
      const port = await (navigator as any).serial.requestPort();
      const transport = new Transport(port, true);
      loader = new ESPLoader({ transport, baudrate: 460800, terminal: { clean() {}, writeLine: log.out, write: log.out } } as any);
      return await loader.main();                                   // chip description
    },
    async write(parts, onProgress) {
      if (!loader) throw new Error("not connected");
      const total = parts.reduce((n, p) => n + p.data.length, 0);
      await loader.writeFlash({
        fileArray: parts.map((p) => ({ data: toBinaryString(p.data), address: p.address })),
        flashSize: "keep", flashMode: "keep", flashFreq: "keep", eraseAll: false, compress: true,
        reportProgress: (_i: number, written: number) => onProgress(Math.round((100 * written) / total)),
      } as any);
    },
    async reset() { await loader?.after("hard_reset"); },
  };
}

export function setupInstaller(profile: BoardProfile, els: { connect: HTMLElement; runtime: HTMLButtonElement; app: HTMLButtonElement; chip: HTMLElement; progress: HTMLProgressElement },
                               currentApp: () => LoadedApp | undefined, con: Console, flasher: Flasher = esptoolFlasher(con)) {
  const progress = (pct: number) => { els.progress.hidden = false; els.progress.value = pct; };
  const busy = async (label: string, fn: () => Promise<void>) => {
    els.runtime.disabled = els.app.disabled = true;
    try { con.out(`${label}…`); await fn(); await flasher.reset(); con.out(`${label} done`); }
    catch (e) { con.err(`${label} failed: ${(e as Error).message}`); }
    finally { els.runtime.disabled = els.app.disabled = false; els.progress.hidden = true; }
  };
  els.connect.addEventListener("click", async () => {
    try {
      const chip = await flasher.connect(); els.chip.textContent = chip;
      checkChip(profile.chip, chip);
      els.runtime.disabled = false; els.app.disabled = !currentApp();
    } catch (e) { con.err((e as Error).message); els.runtime.disabled = els.app.disabled = true; }
  });
  els.runtime.addEventListener("click", () => busy("Install runtime", async () => {
    const manifest = parseManifest(await (await fetch(profile.firmwareManifest)).json());
    const base = profile.firmwareManifest.slice(0, profile.firmwareManifest.lastIndexOf("/") + 1);
    const parts = await Promise.all(manifest.parts.map(async (p) => ({ data: new Uint8Array(await (await fetch(base + p.path)).arrayBuffer()), address: p.offset })));
    await flasher.write(parts, progress);
  }));
  els.app.addEventListener("click", () => busy("Install app", async () => {
    const app = currentApp(); if (!app) throw new Error("load an app first");
    await flasher.write([{ data: app.bytes, address: profile.appOffset }], progress);
  }));
}
```
`pnpm add esptool-js@0.7.0`. The `as any` casts cover differences between 0.7 typings and the README; if `LoaderOptions` requires `enableTracing`, add `enableTracing: false`.

- [ ] **Step 5: Run tests, verify they pass**

Run: `cd web && pnpm test && pnpm build`
Expected: PASS (both installer tests, flash helpers), build OK.

- [ ] **Step 6: Commit**

```bash
git add web
git commit -m "feat(web): Web Serial installer with esptool-js"
```

---

### Task 10: Firmware image for the M5StickC Plus 2

**Files:**
- Create: `firmware/m5stickc_plus2/partitions.csv`, `firmware/m5stickc_plus2/sdkconfig.m5stickc_plus2`, `firmware/m5stickc_plus2/patches/0001-get_board-stick_cplus2.patch`, `firmware/m5stickc_plus2/manifest.template.json`, `firmware/build.sh`, `scripts/firmware.sh`, `.github/workflows/firmware.yml`
- Test: `firmware/check_partitions.py`

**Interfaces:**
- Produces release assets on tag `firmware-m5stickc_plus2-v<semver>`: `AtomVM-m5stickc_plus2-<semver>.img` (flash at `0x1000`), `manifest-m5stickc_plus2.json` matching `FirmwareManifest` from Task 9, and `.sha256` files.
- Consumes `ATOMVM_VERSION`, the pinned `atomvm_m5` commit.

- [ ] **Step 1: Partition table and its check**

`firmware/m5stickc_plus2/partitions.csv`:
```csv
# M5StickC Plus 2 (8 MB flash). First 4 MB identical to AtomVM 0.7 partitions-elixir.csv.
# Name,     Type, SubType, Offset,   Size,     Flags
nvs,        data, nvs,     0x9000,   0x6000,
phy_init,   data, phy,     0xf000,   0x1000,
factory,    app,  factory, 0x10000,  0x1C0000,
boot.avm,   data, phy,     0x1D0000, 0x80000,
main.avm,   data, phy,     0x250000, 0x100000,
apps,       data, 0x40,    0x350000, 0x4B0000,
```
`firmware/check_partitions.py` (fails on overlap, misalignment, or exceeding 8 MB; also pins the two offsets the installer relies on):
```python
#!/usr/bin/env python3
import csv, sys
rows = [r for r in csv.reader(open(sys.argv[1])) if r and not r[0].startswith("#")]
parts = [(r[0].strip(), int(r[3], 16), int(r[4], 16)) for r in rows]
end = 0x8000 + 0x1000
for name, off, size in parts:
    assert off % 0x1000 == 0 and size % 0x1000 == 0, f"{name} not 4 KiB aligned"
    assert off >= end, f"{name} overlaps previous partition (starts 0x{off:X}, previous ends 0x{end:X})"
    end = off + size
assert end <= 0x800000, f"table ends at 0x{end:X} > 8 MiB"
d = {n: (o, s) for n, o, s in parts}
assert d["main.avm"][0] == 0x250000, "main.avm must stay at 0x250000 (installer appOffset)"
assert d["boot.avm"][0] == 0x1D0000
assert d["apps"][0] + d["apps"][1] == 0x800000, "apps must fill the flash"
print(f"OK: {len(parts)} partitions, ends at 0x{end:X}")
```
Run: `python3 firmware/check_partitions.py firmware/m5stickc_plus2/partitions.csv` → `OK: 6 partitions, ends at 0x800000`. Add it to `scripts/test.sh`.

- [ ] **Step 2: sdkconfig overrides and the `get_board` patch**

`firmware/m5stickc_plus2/sdkconfig.m5stickc_plus2` (applied after AtomVM's generated `sdkconfig.defaults`; later files win):
```
CONFIG_ESPTOOLPY_FLASHSIZE_4MB=n
CONFIG_ESPTOOLPY_FLASHSIZE_8MB=y
CONFIG_ESPTOOLPY_FLASHSIZE="8MB"
CONFIG_PARTITION_TABLE_CUSTOM=y
CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions-elixir.csv"
CONFIG_ESP_MAIN_TASK_STACK_SIZE=8192
```
PSRAM stays off in milestone 1 (M5Unified does not need it; AtomVM's own images have it off). The spec's "PSRAM on" line is amended by this task.

`firmware/m5stickc_plus2/patches/0001-get_board-stick_cplus2.patch` (unified diff against `nifs/atomvm_m5.cc` at the pinned commit; the `#else` branch is the plain ESP32 one):
```diff
--- a/nifs/atomvm_m5.cc
+++ b/nifs/atomvm_m5.cc
@@ -91,6 +91,8 @@ static term nif_get_board(Context* ctx, int argc, term argv[])
     case m5::board_t::board_M5StickCPlus:
         return MAKE_ATOM(ctx, "\xB", "stick_cplus");
+    case m5::board_t::board_M5StickCPlus2:
+        return MAKE_ATOM(ctx, "\xC", "stick_cplus2");
     case m5::board_t::board_M5StackCoreInk:
         return MAKE_ATOM(ctx, "\x8", "core_ink");
```
Regenerate the hunk header with `git diff` inside the checked-out `atomvm_m5` if the line numbers differ; `git apply --3way` tolerates small offsets. Open the same change as a PR upstream (`pguyot/atomvm_m5`) and note the PR URL in `firmware/m5stickc_plus2/README.md`.

- [ ] **Step 3: Build script (runs inside the IDF container; CI and local use the same file)**

`firmware/build.sh`:
```bash
#!/usr/bin/env bash
# Usage (inside espressif/idf:v5.5.1 with OTP+Elixir installed): firmware/build.sh <board> <atomvm_version> <atomvm_m5_commit> <out_dir>
set -euo pipefail
BOARD=$1; ATOMVM_VERSION=$2; M5_COMMIT=$3; OUT=$(realpath "$4")
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-/tmp/atomvm-build}; mkdir -p "$WORK" "$OUT"; cd "$WORK"
[ -d AtomVM ] || git clone --depth 1 --branch "$ATOMVM_VERSION" https://github.com/atomvm/AtomVM.git
cd AtomVM
# 1. Host build of the Erlang/Elixir boot libraries (needed by mkimage for boot.avm).
mkdir -p build && (cd build && cmake .. -DAVM_DISABLE_SMP=OFF >/dev/null && make -C libs -j"$(nproc)")
# 2. Add atomvm_m5 as an ESP-IDF component and patch it.
COMP=src/platforms/esp32/components/atomvm_m5
if [ ! -d "$COMP" ]; then git clone https://github.com/pguyot/atomvm_m5.git "$COMP"; fi
(cd "$COMP" && git checkout -q "$M5_COMMIT" && git apply --3way "$HERE/$BOARD/patches/"*.patch || git diff --quiet || true)
# 3. Board partition table replaces the Elixir one (AtomVM's CMake selects partitions-elixir.csv when Elixir support is on).
cp "$HERE/$BOARD/partitions.csv" src/platforms/esp32/partitions-elixir.csv
# 4. Build with ESP-IDF.
cd src/platforms/esp32
. "$IDF_PATH/export.sh"
rm -rf build sdkconfig
idf.py -DATOMVM_ELIXIR_SUPPORT=on set-target esp32
SDKCONFIG_DEFAULTS="sdkconfig.defaults;$HERE/$BOARD/sdkconfig.$BOARD" idf.py -DATOMVM_ELIXIR_SUPPORT=on reconfigure
idf.py -DATOMVM_ELIXIR_SUPPORT=on build
./build/mkimage.sh
VERSION=${FW_VERSION:-dev}
IMG="AtomVM-$BOARD-$VERSION.img"
cp build/atomvm-esp32-elixir.img "$OUT/$IMG"
(cd "$OUT" && sha256sum "$IMG" > "$IMG.sha256")
sed -e "s/@VERSION@/$VERSION/" -e "s/@ATOMVM@/$ATOMVM_VERSION/" -e "s/@IMG@/$IMG/" "$HERE/$BOARD/manifest.template.json" > "$OUT/manifest-$BOARD.json"
echo "built $OUT/$IMG"
```
`firmware/m5stickc_plus2/manifest.template.json`:
```json
{ "version": "@VERSION@", "chip": "ESP32", "atomvm": "@ATOMVM@",
  "parts": [ { "path": "@IMG@", "offset": 4096 } ], "appOffset": 2424832 }
```
`mkimage.sh` writes the bootloader at the ESP32 bootloader offset `0x1000` as the first segment, so the image is flashed at `0x1000` (AtomVM's own `flash.sh` uses `FLASH_OFFSET=0x1000`).

`scripts/firmware.sh` (local wrapper):
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
M5_COMMIT=968508c77c90af5a0109bcd7f0e28a5fa8624c02
docker run --rm -v "$PWD:/repo" -w /repo -e FW_VERSION="${FW_VERSION:-dev}" "$IDF_IMAGE" bash -lc '
  set -e
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git cmake gperf zlib1g-dev erlang elixir rebar3 >/dev/null
  WORK=/repo/firmware/.work firmware/build.sh m5stickc_plus2 "'"$ATOMVM_VERSION"'" '"$M5_COMMIT"' firmware/out'
```
Debian's `elixir` package may be older than 1.14; if `make -C libs` fails on Elixir, install via `apt install -y erlang` plus a precompiled Elixir tarball (`https://github.com/elixir-lang/elixir/releases/download/v1.18.4/elixir-otp-27.zip` unzipped to `/opt/elixir`, add `/opt/elixir/bin` to `PATH`). Add `firmware/.work/ firmware/out/` to `.gitignore`.

- [ ] **Step 4: CI workflow**

`.github/workflows/firmware.yml`:
```yaml
name: firmware
on:
  push:
    tags: ["firmware-m5stickc_plus2-v*"]
    paths: ["firmware/**", ".github/workflows/firmware.yml"]
  pull_request:
    paths: ["firmware/**", ".github/workflows/firmware.yml"]
  workflow_dispatch:
permissions: { contents: write }
jobs:
  build:
    runs-on: ubuntu-latest
    container: espressif/idf:v5.5.1
    env: { ATOMVM_VERSION: v0.7.0-beta.0, M5_COMMIT: 968508c77c90af5a0109bcd7f0e28a5fa8624c02 }
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with: { otp-version: "28", elixir-version: "1.19", rebar3-version: "3.25.1" }
      - run: apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git cmake gperf zlib1g-dev
      - run: git config --global --add safe.directory '*'
      - run: python3 firmware/check_partitions.py firmware/m5stickc_plus2/partitions.csv
      - name: Build image
        run: |
          case "$GITHUB_REF" in refs/tags/firmware-m5stickc_plus2-v*) export FW_VERSION="${GITHUB_REF#refs/tags/firmware-m5stickc_plus2-v}";; esac
          WORK=/tmp/atomvm firmware/build.sh m5stickc_plus2 "$ATOMVM_VERSION" "$M5_COMMIT" out
      - uses: actions/upload-artifact@v4
        with: { name: firmware-m5stickc_plus2, path: out/* }
      - uses: softprops/action-gh-release@v2
        if: startsWith(github.ref, 'refs/tags/firmware-m5stickc_plus2-v')
        with: { files: out/* }
```
The board profile's `firmwareManifest` points at `releases/latest/download/manifest-m5stickc_plus2.json`; GitHub resolves `latest` to the newest non-prerelease release, so tag firmware releases as full releases.

- [ ] **Step 5: Build locally and verify on the watch**

Run: `mise run firmware` (first run takes 20 to 40 minutes: IDF component download, M5Unified/M5GFX fetch, two builds).
Expected: `built firmware/out/AtomVM-m5stickc_plus2-dev.img` (about 2.3 MB) and `manifest-m5stickc_plus2.json`.

Flash from the terminal to confirm before trusting the web installer:
```bash
esptool.py --chip esp32 --port /dev/cu.usbserial-* --baud 921600 write_flash 0x1000 firmware/out/AtomVM-m5stickc_plus2-dev.img
esptool.py --chip esp32 --port /dev/cu.usbserial-* write_flash 0x250000 m5_emu/test/smoke_app/_build/default/lib/smoke_app.avm
```
Then `screen /dev/cu.usbserial-* 115200`. Expected: AtomVM banner, then the smoke app prints `SMOKE board stick_cplus2 135x240` (this proves the patch) and the screen shows a red rectangle and "hello". `SMOKE a_pressed` will be `false` on the device (there is no `m5emu.pressA`); `emscripten:run_script/2` is `undef` on ESP32, so wrap that call in the smoke app with `catch` before this step: `catch emscripten:run_script(...)`. The throughput lines print real-hardware numbers; note them in `firmware/m5stickc_plus2/README.md`.

If the display stays black: run `idf.py menuconfig` and confirm `AVM_M5_DISPLAY_ENABLE=y`; check M5GFX autodetect logs on the serial console (`[Autodetect] M5StickCPlus2`).

- [ ] **Step 6: Commit**

```bash
git add firmware scripts/firmware.sh scripts/test.sh .github/workflows/firmware.yml .gitignore m5_emu/test/smoke_app
git commit -m "feat(firmware): M5StickC Plus 2 runtime image with 8 MB partition table"
```

---

### Task 11: `examples/clock` and the end-to-end test

**Files:**
- Create: `examples/clock/mix.exs`, `examples/clock/lib/clock.ex`, `examples/clock/README.md`
- Create: `web/playwright.config.ts`, `web/e2e/clock.spec.ts`, `scripts/build-example.sh`
- Modify: `scripts/test.sh`, `web/package.json`

**Interfaces:**
- Produces `web/e2e/fixtures/clock.avm` (committed, rebuilt by `scripts/build-example.sh`).
- The example uses only `m5`, `m5_display`, `m5_btn_a`, `m5_btn_b`, `m5_btn_pwr`, `m5_speaker`, `gpio`.

- [ ] **Step 1: The example app**

`examples/clock/mix.exs`:
```elixir
defmodule Clock.MixProject do
  use Mix.Project
  def project do
    [app: :clock, version: "0.1.0", elixir: "~> 1.15", start_permanent: false, deps: deps(),
     atomvm: [start: Clock, esp32_flash_offset: 0x250000]]
  end
  def application, do: [extra_applications: []]
  defp deps do
    [{:exatomvm, git: "https://github.com/atomvm/exatomvm.git", runtime: false},
     {:atomvm, "~> 0.7.0-beta.0", runtime: false},
     {:atomvm_m5, git: "https://github.com/pguyot/atomvm_m5.git", ref: "968508c77c90af5a0109bcd7f0e28a5fa8624c02", manager: :rebar3}]
  end
end
```
`examples/clock/lib/clock.ex`:
```elixir
defmodule Clock do
  @moduledoc "Reference app: clock face, button-driven screens, beep and LED. Runs in the emulator and on the watch."
  @led 19
  @screens [:clock, :buttons, :about]

  def start do
    :m5.begin_([])
    :m5_display.set_rotation(1)
    :gpio.set_pin_mode(@led, :output)
    loop(%{screen: 0, led: false, last_draw: 0, boot: :erlang.monotonic_time(:second)})
  end

  defp loop(state) do
    :timer.sleep(10)
    :m5.update()
    state = state |> handle_a() |> handle_b() |> handle_pwr()
    state = maybe_draw(state)
    loop(state)
  end

  defp handle_a(state) do
    if :m5_btn_a.was_pressed(), do: %{state | screen: rem(state.screen + 1, length(@screens)), last_draw: 0}, else: state
  end

  defp handle_b(state) do
    if :m5_btn_b.was_pressed() do
      :m5_speaker.tone(1800, 80)
      led = not state.led
      :gpio.digital_write(@led, if(led, do: :high, else: :low))
      %{state | led: led, last_draw: 0}
    else
      state
    end
  end

  defp handle_pwr(state) do
    cond do
      :m5_btn_pwr.was_pressed() -> :m5_display.sleep(); state
      :m5_btn_pwr.was_released() -> :m5_display.wakeup(); %{state | last_draw: 0}
      true -> state
    end
  end

  defp maybe_draw(%{last_draw: last} = state) do
    now = :erlang.monotonic_time(:second)
    if now != last, do: (draw(Enum.at(@screens, state.screen), state, now); %{state | last_draw: now}), else: state
  end

  defp draw(:clock, state, now) do
    secs = now - state.boot
    text = :io_lib.format("~2..0B:~2..0B:~2..0B", [div(secs, 3600), rem(div(secs, 60), 60), rem(secs, 60)]) |> :erlang.iolist_to_binary()
    :m5_display.start_write()
    :m5_display.fill_screen(0x000000)
    :m5_display.set_text_size(4)
    :m5_display.draw_center_string(text, div(:m5_display.width(), 2), 40)
    :m5_display.set_text_size(1)
    :m5_display.set_cursor(4, 120)
    :m5_display.print("A: next  B: beep+LED  PWR: sleep")
    :m5_display.end_write()
  end

  defp draw(:buttons, state, _now) do
    :m5_display.start_write()
    :m5_display.fill_screen(0x102040)
    :m5_display.set_text_size(2)
    :m5_display.set_cursor(0, 0)
    :m5_display.println("Buttons")
    :m5_display.set_text_size(1)
    :m5_display.println("A pressed: #{:m5_btn_a.is_pressed()}")
    :m5_display.println("B pressed: #{:m5_btn_b.is_pressed()}")
    :m5_display.println("LED: #{state.led}")
    :m5_display.fill_rect(200, 100, 30, 30, if(state.led, do: 0xFF0000, else: 0x404040))
    :m5_display.end_write()
  end

  defp draw(:about, _state, _now) do
    :m5_display.start_write()
    :m5_display.fill_screen(0x203010)
    :m5_display.set_text_size(2)
    :m5_display.set_cursor(0, 0)
    :m5_display.println("atomvm_watch")
    :m5_display.set_text_size(1)
    :m5_display.println("board: #{:m5.get_board()}")
    :m5_display.println("#{:m5_display.width()}x#{:m5_display.height()}")
    :m5_display.end_write()
  end
end
```
`mix atomvm.check` will warn that `m5_*` functions are "not available" on the AtomVM API list because they come from a component; that is a warning, not an error. Verify `mix deps.get && mix atomvm.packbeam` produces `clock.avm` in the project root.

- [ ] **Step 2: Fixture build script and Playwright setup**

`scripts/build-example.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../examples/clock"
mix deps.get >/dev/null && mix atomvm.packbeam
mkdir -p ../../web/e2e/fixtures && cp clock.avm ../../web/e2e/fixtures/clock.avm
echo "fixture updated: web/e2e/fixtures/clock.avm"
```
`cd web && pnpm add -D @playwright/test && pnpm exec playwright install chromium`.

`web/playwright.config.ts`:
```ts
import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "e2e", timeout: 60_000,
  webServer: { command: "pnpm build && pnpm preview --port 4173", port: 4173, reuseExistingServer: true },
  use: { baseURL: "http://localhost:4173", browserName: "chromium" },
});
```
Vite's `preview` serves `web/dist`; copy the fixture into the served tree in `package.json`: `"prebuild": "mkdir -p public/fixtures && cp e2e/fixtures/clock.avm public/fixtures/clock.avm"`.

- [ ] **Step 3: Write the e2e test**

`web/e2e/clock.spec.ts`:
```ts
import { test, expect, type Page } from "@playwright/test";

async function pixel(page: Page, x: number, y: number) {
  return page.evaluate(([x, y]) => {
    const c = document.getElementById("screen") as HTMLCanvasElement;
    const d = c.getContext("2d")!.getImageData(x, y, 1, 1).data; return [d[0], d[1], d[2]];
  }, [x, y]);
}
const consoleHas = (page: Page, re: RegExp) => expect.poll(() => page.locator("#console").innerText(), { timeout: 30_000 }).toMatch(re);

test("clock app boots, reacts to buttons, and can be replaced", async ({ page }) => {
  const tones: any[] = [];
  await page.addInitScript(() => { (window as any).__tones = []; const P = (window as any).AudioContext?.prototype; if (P) { const o = P.createOscillator; P.createOscillator = function () { (window as any).__tones.push(1); return o.call(this); }; } });
  await page.goto("/?avm=/fixtures/clock.avm");
  // Boot: the clock screen is black with white digits; the canvas is native 135x240 and rotation 1 is applied.
  await expect.poll(async () => (await pixel(page, 5, 5)).join(","), { timeout: 30_000 }).toBe("0,0,0");
  await expect.poll(async () => { // some white pixel exists in the digits band
    return page.evaluate(() => { const c = document.getElementById("screen") as HTMLCanvasElement; const d = c.getContext("2d")!.getImageData(0, 0, c.width, c.height).data; for (let i = 0; i < d.length; i += 4) if (d[i] === 255 && d[i + 1] === 255 && d[i + 2] === 255) return true; return false; });
  }, { timeout: 30_000 }).toBe(true);
  // Button A -> "buttons" screen has a blue background 0x102040.
  await page.click('[data-btn="a"]');
  await expect.poll(async () => (await pixel(page, 5, 5)).join(","), { timeout: 10_000 }).toBe("16,32,64");
  // Button B -> tone and LED.
  await page.click('[data-btn="b"]');
  await expect.poll(() => page.evaluate(() => (window as any).__tones.length)).toBeGreaterThan(0);
  await expect(page.locator("#led")).toHaveClass(/on/);
  // Replace app: dropping the same file again reloads the page and reboots from the clock screen.
  await page.setInputFiles("#file", "e2e/fixtures/clock.avm");
  await page.waitForLoadState("load");
  await expect.poll(async () => (await pixel(page, 5, 5)).join(","), { timeout: 30_000 }).toBe("0,0,0");
  await consoleHas(page, /./); // console pane exists and is populated after reboot
  expect(tones).toBeDefined();
});
```
Pixel coordinates are native framebuffer coordinates; at rotation 1 the logical top-left of the screen maps to native `(134, 0)`, but a full-screen fill makes `(5,5)` valid regardless.

- [ ] **Step 4: Run it**

Run: `scripts/build-example.sh && cd web && pnpm exec playwright test`
Expected: PASS. Failure modes and what they mean:
- Console shows `Failed opening blob:` → apply the service-worker fallback from Task 8.
- Console shows `SharedArrayBuffer is not defined` → the preview server lost the COOP/COEP headers; check `vite.config.ts` `preview.headers`.
- `m5emu.exec` never called → `boardReady` handshake failed; check `window.m5emu` is assigned before the VM starts.

- [ ] **Step 5: Wire into `scripts/test.sh`, document, commit**

Append to `scripts/test.sh`: `(cd web && pnpm exec playwright test)`. Add `"e2e": "playwright test"` to `web/package.json`. Write `examples/clock/README.md` with the three commands: `mix deps.get`, `mix atomvm.packbeam`, `mix atomvm.esp32.flash --port /dev/cu.usbserial-*`.

Manual device check (record results in `firmware/m5stickc_plus2/README.md`): flash `clock.avm` with `mix atomvm.esp32.flash`; confirm the same three screens, beep and LED, power button sleep/wake; then install the same `.avm` through the web page and confirm the install takes under five seconds.

```bash
git add examples scripts web
git commit -m "feat: clock example app and Playwright end-to-end test"
```

---

### Task 12: `mix m5.emulate`

**Files:**
- Create: `m5_emu_mix/mix.exs`, `m5_emu_mix/lib/mix/tasks/m5.emulate.ex`, `m5_emu_mix/lib/m5_emu_mix/server.ex`, `m5_emu_mix/test/server_test.exs`, `scripts/build-web.sh`
- Modify: `web/src/main.ts` (dev reload polling), `examples/clock/mix.exs` (add the dev dependency)

**Interfaces:**
- Produces `M5EmuMix.Server.start(opts) :: {:ok, pid}` with `opts = [port: integer, web_dir: path, avm: path]`; serves `web_dir` statically with COOP/COEP headers, `GET /app.avm` (the packed app), `GET /__version` (mtime of the avm as text).
- The page, when `?dev=1`, polls `/__version` every second and reloads when it changes.

- [ ] **Step 1: Failing test**

`m5_emu_mix/test/server_test.exs`:
```elixir
defmodule M5EmuMix.ServerTest do
  use ExUnit.Case
  setup do
    dir = Path.join(System.tmp_dir!(), "m5emu_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir); File.write!(Path.join(dir, "index.html"), "<h1>hi</h1>")
    avm = Path.join(dir, "app.avm"); File.write!(avm, <<1, 2, 3>>)
    {:ok, pid} = M5EmuMix.Server.start(port: 0, web_dir: dir, avm: avm)
    port = M5EmuMix.Server.port(pid)
    %{port: port, avm: avm}
  end
  defp get(port, path) do
    {:ok, {{_, status, _}, headers, body}} = :httpc.request(:get, {~c"http://127.0.0.1:#{port}#{path}", []}, [], body_format: :binary)
    {status, Map.new(headers, fn {k, v} -> {to_string(k), to_string(v)} end), body}
  end
  test "serves static files with isolation headers", %{port: port} do
    {200, h, body} = get(port, "/index.html")
    assert body == "<h1>hi</h1>"
    assert h["cross-origin-opener-policy"] == "same-origin"
    assert h["cross-origin-embedder-policy"] == "require-corp"
  end
  test "serves the app and a version that changes on rewrite", %{port: port, avm: avm} do
    {200, _, <<1, 2, 3>>} = get(port, "/app.avm")
    {200, _, v1} = get(port, "/__version")
    Process.sleep(1100); File.write!(avm, <<4>>)
    {200, _, v2} = get(port, "/__version")
    assert v1 != v2
  end
end
```
Run: `cd m5_emu_mix && mix test` → FAIL (module missing). `:inets` must be started in `test_helper.exs`: `Application.ensure_all_started(:inets)`.

- [ ] **Step 2: Implement the server with Bandit + Plug**

`m5_emu_mix/mix.exs` deps: `{:bandit, "~> 1.6"}, {:plug, "~> 1.16"}`; `elixirc_paths` default; `app: :m5_emu_mix`.

`m5_emu_mix/lib/m5_emu_mix/server.ex`:
```elixir
defmodule M5EmuMix.Server do
  @moduledoc false
  def start(opts) do
    {:ok, pid} = Bandit.start_link(plug: {M5EmuMix.Plug, opts}, port: Keyword.get(opts, :port, 4174), ip: {127, 0, 0, 1})
    {:ok, pid}
  end
  def port(pid), do: (fn {:ok, {_ip, port}} -> port end).(ThousandIsland.listener_info(pid))
end

defmodule M5EmuMix.Plug do
  @behaviour Plug
  import Plug.Conn
  @impl true
  def init(opts), do: Map.new(opts)
  @impl true
  def call(conn, %{web_dir: dir, avm: avm}) do
    conn = conn |> put_resp_header("cross-origin-opener-policy", "same-origin") |> put_resp_header("cross-origin-embedder-policy", "require-corp")
    case conn.request_path do
      "/app.avm" -> send_file(conn |> put_resp_content_type("application/octet-stream"), 200, avm)
      "/__version" -> send_resp(conn |> put_resp_content_type("text/plain"), 200, to_string(File.stat!(avm, time: :posix).mtime))
      path ->
        file = Path.join(dir, if(path == "/", do: "index.html", else: String.trim_leading(path, "/")))
        if File.regular?(file), do: send_file(conn |> put_resp_content_type(MIME.from_path(file)), 200, file), else: send_resp(conn, 404, "not found")
    end
  end
end
```
Bandit returns a `ThousandIsland` listener; `ThousandIsland.listener_info/1` gives the bound port. Run `mix test` → PASS.

- [ ] **Step 3: The mix task**

`m5_emu_mix/lib/mix/tasks/m5.emulate.ex`:
```elixir
defmodule Mix.Tasks.M5.Emulate do
  use Mix.Task
  @shortdoc "Pack the app and open it in the atomvm_watch emulator, rebuilding on change"
  @moduledoc """
  Runs `mix atomvm.packbeam`, serves the emulator page with the headers AtomVM needs, opens the browser,
  and re-packs when files under lib/ change.

      mix m5.emulate [--port 4174] [--web-dir path/to/web/dist] [--no-open]
  """
  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [port: :integer, web_dir: :string, open: :boolean])
    Mix.Task.run("app.config")
    web_dir = opts[:web_dir] || Application.app_dir(:m5_emu_mix, "priv/web")
    unless File.exists?(Path.join(web_dir, "index.html")), do: Mix.raise("emulator page not found in #{web_dir}; run scripts/build-web.sh or pass --web-dir")
    avm = pack!()
    {:ok, pid} = M5EmuMix.Server.start(port: opts[:port] || 4174, web_dir: web_dir, avm: avm)
    port = M5EmuMix.Server.port(pid)
    url = "http://localhost:#{port}/?dev=1&avm=http://localhost:#{port}/app.avm"
    Mix.shell().info("emulator at #{url}")
    if Keyword.get(opts, :open, true), do: System.cmd(open_cmd(), [url])
    watch_loop(avm, mtimes())
  end
  defp pack! do
    Mix.Task.rerun("atomvm.packbeam")
    Path.join(File.cwd!(), "#{Mix.Project.config()[:app]}.avm")
  end
  defp mtimes, do: Path.wildcard("lib/**/*.{ex,erl}") |> Map.new(&{&1, File.stat!(&1).mtime})
  defp watch_loop(avm, seen) do
    Process.sleep(500)
    now = mtimes()
    if now != seen do
      Mix.shell().info("change detected, repacking…")
      try do pack!() rescue e -> Mix.shell().error(Exception.message(e)) end
    end
    watch_loop(avm, now)
  end
  defp open_cmd, do: (case :os.type() do {:unix, :darwin} -> "open"; {:unix, _} -> "xdg-open"; _ -> "start" end)
end
```
`scripts/build-web.sh`: `cd web && pnpm build && rm -rf ../m5_emu_mix/priv/web && mkdir -p ../m5_emu_mix/priv && cp -R dist ../m5_emu_mix/priv/web && cp public/m5_emu.avm ../m5_emu_mix/priv/web/` (the `.avm` must be present in the served dir; `vite build` copies `public/` into `dist/` already, so the last `cp` is a safety net).

- [ ] **Step 4: Dev reload in the page**

In `web/src/main.ts`, after `run(...)` is wired:
```ts
if (params.get("dev") === "1") {
  let last: string | undefined;
  setInterval(async () => {
    try { const v = await (await fetch("/__version", { cache: "no-store" })).text(); if (last && v !== last) location.reload(); last = v; } catch {}
  }, 1000);
}
```
Add `{:m5_emu_mix, path: "../../m5_emu_mix", only: :dev, runtime: false}` to `examples/clock/mix.exs` deps.

- [ ] **Step 5: Verify**

Run: `scripts/build-web.sh && cd examples/clock && mix m5.emulate`
Expected: browser opens on the clock app. Edit `lib/clock.ex` (change a string), save: terminal prints "change detected, repacking…", page reloads within about two seconds showing the new text.

```bash
git add m5_emu_mix scripts/build-web.sh web/src/main.ts examples/clock/mix.exs
git commit -m "feat(mix): mix m5.emulate dev loop"
```

---

### Task 13: CI, GitHub Pages deploy, docs

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/workflows/pages.yml`, `firmware/m5stickc_plus2/README.md`, `docs/device-checklist.md`
- Modify: `README.md`, `docs/superpowers/specs/2026-10-03-atomvm-watch-design.md` (two amendments)

- [ ] **Step 1: CI**

`.github/workflows/ci.yml`:
```yaml
name: ci
on: { push: { branches: [main] }, pull_request: {} }
jobs:
  test:
    runs-on: ubuntu-latest
    env: { ATOMVM_VERSION: v0.7.0-beta.0 }
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: mise run setup
      - run: cd web && pnpm exec playwright install --with-deps chromium
      - run: mise run test
```
`mise-action` installs the pinned Erlang, Elixir, Node, pnpm and Python; `mise run test` runs eunit, the node smoke test, vitest, the partition check and Playwright in that order.

- [ ] **Step 2: Pages**

`.github/workflows/pages.yml`:
```yaml
name: pages
on: { push: { branches: [main] }, workflow_dispatch: {} }
permissions: { contents: read, pages: write, id-token: write }
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: { name: github-pages, url: ${{ steps.deploy.outputs.page_url }} }
    env: { ATOMVM_VERSION: v0.7.0-beta.0 }
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: mise run setup && scripts/build-m5-emu.sh && (cd web && pnpm build)
      - uses: actions/upload-pages-artifact@v3
        with: { path: web/dist }
      - id: deploy
        uses: actions/deploy-pages@v4
      - name: Smoke the deployment
        run: |
          curl -fsSI "${{ steps.deploy.outputs.page_url }}" | head -1
          curl -fsSI "${{ steps.deploy.outputs.page_url }}atomvm/AtomVM.wasm" | grep -i 'content-type: application/wasm'
```
`vite.config.ts` already uses `base: "./"`, so the site works under `https://tomashco.github.io/atomvm_watch/`. Enable Pages (Settings → Pages → Source: GitHub Actions) once.

- [ ] **Step 3: Docs**

`docs/device-checklist.md`: the manual steps from Tasks 10 and 11 as a checklist with expected observations (banner on serial, three screens, beep, LED, sleep/wake, web install time).
`firmware/m5stickc_plus2/README.md`: what the image contains, the partition table, the upstream `get_board` PR link, measured throughput numbers.
`README.md`: replace the "Tasks are wired up as milestone 1 lands" line with the Pages URL and a three-step quick start (open the page, drop `clock.avm` from the latest release, Install runtime then Install app).

Spec amendments (section 5 and section 6): the wasm binaries are fetched by `scripts/fetch-atomvm.sh` and verified by sha256 instead of being committed; PSRAM is off in milestone 1.

- [ ] **Step 4: Verify and commit**

Run: `mise run test` locally (everything green), push, confirm `ci` and `pages` workflows pass and the Pages URL loads the emulator with the clock fixture via `?avm=./fixtures/clock.avm`.

```bash
git add .github README.md docs firmware/m5stickc_plus2/README.md
git commit -m "ci: test workflow, GitHub Pages deploy, device checklist"
```

---

## Self-review notes

- Spec coverage: §3 deliverables → Tasks 1, 3–9 (m5_emu, web), 10 (firmware), 12 (mix), 11 (example); §4.1 module surface → Tasks 3–5 plus the drift test; §4.3 protocol → Tasks 3 and 7; §5 page files → Tasks 1, 7, 8, 9; §6 → Task 10; §7 → Tasks 11, 12; §8 testing → each task plus Task 11 e2e and the device checklist; §9 error handling → Task 8 (VM exit, bad `.avm`), Task 9 (installer errors), Task 5 (`{error, unsupported}`); §12 risks → Task 6 (shadowing, throughput), Task 11 (fonts vs photos is manual, listed in the checklist), Task 13 (Pages smoke).
- Deviations from the spec, both recorded in Task 13: wasm binaries fetched not committed; PSRAM off.
- Known soft spot: blob URL loading inside the pthread worker (Task 8) has a documented fallback and is exercised by the Task 11 e2e test before anything depends on it.

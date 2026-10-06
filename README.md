# atomvm_watch

A platform for running [AtomVM](https://github.com/atomvm/AtomVM) apps on ESP32 watches: a browser emulator, a web installer, and board profiles. The first supported board is the [M5StickC Plus 2](https://docs.m5stack.com/en/core/M5StickC%20PLUS2).
Write apps in Elixir, Erlang or Gleam against
[atomvm_m5](https://github.com/pguyot/atomvm_m5), run them in the browser, then flash them to the
watch over USB from the same page. Think Bangle.js app loader, for the BEAM.

Status: pre-alpha, milestone 1 (single app: emulate, flash runtime, flash app).
Milestone 2 is the on-device app loader ("app store"). See `docs/superpowers/specs/`.

## Prerequisites

- [Nix](https://nixos.org/download) and [devenv](https://devenv.sh) — provide every language tool
  below. Tool caches (hex, mix, rebar3, pnpm, Playwright browsers) stay in `.devenv/` inside the repo.
- Optional: [direnv](https://direnv.net), to enter the environment automatically on `cd`.
- Docker — only for building the ESP32 runtime image locally (ESP-IDF 5.5 runs in a container);
  CI builds it otherwise.
- Chrome or Edge — Web Serial is needed to flash from the browser.
- An M5StickC Plus 2 and a USB-C data cable.

## Setup

```sh
git clone <this repo> && cd atomvm_watch
devenv shell          # Erlang 27, Elixir 1.18, rebar3, Node 22, pnpm 10, Python 3.12, esptool
setup                 # deps.get, pnpm install, Playwright browsers
```

With direnv, run `direnv allow` once instead of `devenv shell`.

## Daily workflow

Inside the devenv shell:

```sh
dev                   # emulator at http://localhost:5173 with examples/clock preloaded
run-tests             # Erlang unit tests, JS renderer tests, Playwright e2e
firmware              # builds firmware/m5stickc_plus2/AtomVM-m5stickc-plus2.img in Docker
```

Each also works from outside the shell, for example `devenv shell -- run-tests`.

First time on a watch: open the emulator page, plug the watch in, click **Install runtime**.
After that **Install app** writes only the app `.avm` (about a second).

Terminal alternative for the app, from an exatomvm project:

```sh
mix atomvm.esp32.flash --port /dev/cu.usbserial-*
```

## Repository layout

| Path | What |
|------|------|
| `m5_emu/` | Erlang library that implements the `atomvm_m5` API for the browser VM |
| `web/` | Emulator page, display renderer, Web Serial installer |
| `m5_emu_mix/` | `mix m5.emulate` task for Elixir projects |
| `examples/clock/` | Reference Elixir app |
| `boards/` | Board profiles: screen, buttons, device image, firmware manifest (first: `m5stickc_plus2`) |
| `firmware/` | Partition tables and CI workflow for the ESP32 runtime images |
| `docs/` | Specs and plans (`superpowers/`), overview docs (`overview/`) |

Tasks are wired up as milestone 1 lands; `devenv.nix` is the single source of truth for tools and tasks.

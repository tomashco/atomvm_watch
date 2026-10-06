# Tool versions and tasks for atomvm_watch. Install Nix and devenv (https://devenv.sh), then
# `devenv shell` (or `direnv allow` once). Versions are pinned by devenv.lock.
{ pkgs, config, ... }:

let
  beam = pkgs.beam.packages.erlang_27;
  state = config.devenv.state;
in
{
  packages = [
    beam.rebar3
    pkgs.esptool
    # build-atomvmlib.sh (AtomVM libs only, no native VM)
    pkgs.cmake
    pkgs.gperf
    pkgs.ninja
    pkgs.curl
    pkgs.zlib
  ];

  # Pinned versions (ATOMVM_VERSION, ATOMVM_M5_COMMIT) live in versions.env, the single source.
  dotenv.enable = true;
  dotenv.filename = "versions.env";

  languages.erlang = {
    enable = true;
    package = beam.erlang;
  };
  languages.elixir = {
    enable = true;
    package = beam.elixir_1_18;
  };
  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_22;
    pnpm = {
      enable = true;
      package = pkgs.pnpm_10;
    };
  };
  languages.python = {
    enable = true;
    package = pkgs.python312;
  };

  env = {
    # ESP-IDF image used for firmware builds (same as atomvm_m5 CI).
    IDF_IMAGE = "espressif/idf:v5.5.1";

    # Keep every tool cache inside the repo (.devenv/state, git-ignored) instead of $HOME.
    MIX_HOME = "${state}/mix";
    HEX_HOME = "${state}/hex";
    REBAR_CACHE_DIR = "${state}/rebar3/cache";
    REBAR_GLOBAL_CONFIG_DIR = "${state}/rebar3/config";
    npm_config_store_dir = "${state}/pnpm-store";
    npm_config_cache = "${state}/npm-cache";
    PLAYWRIGHT_BROWSERS_PATH = "${state}/ms-playwright";
  };

  scripts = {
    setup = {
      description = "Install Erlang, Elixir, JS and example dependencies";
      exec = ''"$DEVENV_ROOT/scripts/setup.sh" "$@"'';
    };
    dev = {
      description = "Serve the emulator locally with the example app, rebuild on change";
      exec = ''"$DEVENV_ROOT/scripts/dev.sh" "$@"'';
    };
    run-tests = {
      description = "Run Erlang, JS and end-to-end tests";
      exec = ''"$DEVENV_ROOT/scripts/test.sh" "$@"'';
    };
    firmware = {
      description = "Build the ESP32 runtime image (AtomVM + atomvm_m5) in Docker";
      exec = ''"$DEVENV_ROOT/scripts/firmware.sh" "$@"'';
    };
  };

  enterShell = ''
    echo "atomvm_watch: setup | dev | run-tests | firmware   (AtomVM $ATOMVM_VERSION)"
  '';
}

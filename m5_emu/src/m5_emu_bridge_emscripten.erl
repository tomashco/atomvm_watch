-module(m5_emu_bridge_emscripten).
-behaviour(m5_emu_bridge).
-export([run_script/1]).
run_script(Script) -> emscripten:run_script(Script, [main_thread, async]).

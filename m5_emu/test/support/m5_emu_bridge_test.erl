-module(m5_emu_bridge_test).
-behaviour(m5_emu_bridge).
-export([run_script/1]).
run_script(Script) -> m5_emu_test_sink ! {script, iolist_to_binary(Script)}, ok.

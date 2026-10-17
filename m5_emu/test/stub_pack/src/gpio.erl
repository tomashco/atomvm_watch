%% Shadowing fixture: a same-named gpio in a later pack. m5_emu.avm's shim must win.
-module(gpio).
-export([set_pin_mode/2, digital_write/2, digital_read/1]).
set_pin_mode(_, _) -> stub.
digital_write(_, _) -> stub.
digital_read(_) -> stub.

%% Only the on-board LED (pin 19 on the StickC Plus2) is emulated.
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

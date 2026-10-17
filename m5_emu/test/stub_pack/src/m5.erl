%% Shadowing fixture: mimics an app pack that bundles atomvm_m5's own m5 module. m5_emu.avm is
%% loaded first, so AtomVM must never run this one.
-module(m5).
-export([begin_/1, get_board/0, update/0]).
begin_(_) -> ok.
get_board() -> stub_board.
update() -> ok.

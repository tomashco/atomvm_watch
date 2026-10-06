-module(m5_speaker).
-export([is_enabled/0, set_volume/1, get_volume/0, tone/2, tone/3, tone/4, is_playing/0, stop/0]).
-export([play_raw_u8/1, play_raw_u8/2, play_raw_u8/3, play_raw_u8/4, play_raw_u8/5, play_raw_u8/6, play_raw_s8/1, play_raw_s8/2, play_raw_s8/3, play_raw_s8/4, play_raw_s8/5, play_raw_s8/6, play_raw_s16/1, play_raw_s16/2, play_raw_s16/3, play_raw_s16/4, play_raw_s16/5, play_raw_s16/6]).

is_enabled() -> true.
set_volume(V) when is_integer(V), V >= 0, V =< 255 -> m5_emu_display:set_volume(V).
get_volume() -> m5_emu_display:get_volume().
%% Like upstream, tone returns true. Channel and StopCurrent are ignored: one voice.
tone(Freq, Ms) -> m5_emu_display:tone(Freq, Ms).
tone(Freq, Ms, _Channel) -> tone(Freq, Ms).
tone(Freq, Ms, _Channel, _StopCurrent) -> tone(Freq, Ms).
is_playing() -> m5_emu_display:is_playing().
stop() -> m5_emu_display:stop_tone().

play_raw_u8(_) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_u8(_, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_u8(_, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_u8(_, _, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_u8(_, _, _, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_u8(_, _, _, _, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s8(_) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s8(_, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s8(_, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s8(_, _, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s8(_, _, _, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s8(_, _, _, _, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s16(_) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s16(_, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s16(_, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s16(_, _, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s16(_, _, _, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
play_raw_s16(_, _, _, _, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).

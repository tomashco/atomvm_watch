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


%% Raw PCM playback, played by the page through WebAudio. Arguments and defaults follow the NIF:
%% (Data, Rate = 44100, Stereo = false, Repeat = 1, Channel, StopCurrent). Channel and StopCurrent
%% are ignored (one voice); Repeat 0 loops until stop/0. Returns true.
play_raw_u8(D) -> play(u8, D, []).
play_raw_u8(D, R) -> play(u8, D, [R]).
play_raw_u8(D, R, St) -> play(u8, D, [R, St]).
play_raw_u8(D, R, St, Rep) -> play(u8, D, [R, St, Rep]).
play_raw_u8(D, R, St, Rep, _Ch) -> play(u8, D, [R, St, Rep]).
play_raw_u8(D, R, St, Rep, _Ch, _Stop) -> play(u8, D, [R, St, Rep]).
play_raw_s8(D) -> play(s8, D, []).
play_raw_s8(D, R) -> play(s8, D, [R]).
play_raw_s8(D, R, St) -> play(s8, D, [R, St]).
play_raw_s8(D, R, St, Rep) -> play(s8, D, [R, St, Rep]).
play_raw_s8(D, R, St, Rep, _Ch) -> play(s8, D, [R, St, Rep]).
play_raw_s8(D, R, St, Rep, _Ch, _Stop) -> play(s8, D, [R, St, Rep]).
play_raw_s16(D) -> play(s16, D, []).
play_raw_s16(D, R) -> play(s16, D, [R]).
play_raw_s16(D, R, St) -> play(s16, D, [R, St]).
play_raw_s16(D, R, St, Rep) -> play(s16, D, [R, St, Rep]).
play_raw_s16(D, R, St, Rep, _Ch) -> play(s16, D, [R, St, Rep]).
play_raw_s16(D, R, St, Rep, _Ch, _Stop) -> play(s16, D, [R, St, Rep]).

play(Fmt, Data, Opts) ->
    [Rate, Stereo, Repeat] = Opts ++ lists:nthtail(length(Opts), [44100, false, 1]),
    case is_binary(Data) andalso is_integer(Rate) andalso Rate > 0 andalso is_boolean(Stereo)
         andalso is_integer(Repeat) andalso Repeat >= 0 of
        true -> m5_emu_display:play_raw(Fmt, Data, Rate, Stereo, Repeat);
        false -> error(badarg)
    end.

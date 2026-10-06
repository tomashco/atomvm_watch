-module(m5_rtc).
-export([is_enabled/0, get_time/0, get_date/0, get_datetime/0, set_time/1, set_date/1, set_datetime/1]).

%% Emulated RTC: the host's UTC clock plus an offset that set_* adjusts, so an app can set the time
%% and read it back ticking, like the BM8563 on the watch. The offset lives in a public named ETS
%% table owned by the m5_emu_display server (created on first set), so it survives app processes.
-define(TAB, m5_emu_rtc).

is_enabled() -> true.

get_datetime() -> from_seconds(erlang:system_time(second) + offset()).
get_date() -> element(1, get_datetime()).
get_time() -> element(2, get_datetime()).

set_datetime({{Y, Mo, D}, {H, Mi, S}} = DT) when is_integer(Y), is_integer(Mo), is_integer(D),
                                                 is_integer(H), is_integer(Mi), is_integer(S) ->
    set_offset(to_seconds(DT) - erlang:system_time(second));
set_datetime(_) -> error(badarg).
set_date(Date) -> set_datetime({Date, get_time()}).
set_time(Time) -> set_datetime({get_date(), Time}).

offset() ->
    try ets:lookup(?TAB, offset) of
        [{offset, O}] -> O;
        [] -> 0
    catch error:badarg -> 0
    end.

set_offset(O) ->
    case ets:info(?TAB, name) of
        undefined -> m5_emu_display:ensure_table(?TAB);
        _ -> ok
    end,
    true = ets:insert(?TAB, {offset, O}),
    ok.

%% Unix seconds <-> {{Y,M,D},{h,m,s}} (UTC, proleptic Gregorian; Howard Hinnant's civil algorithms).
from_seconds(Secs) ->
    Days = floor_div(Secs, 86400),
    SoD = Secs - Days * 86400,
    {civil_from_days(Days), {SoD div 3600, SoD rem 3600 div 60, SoD rem 60}}.

to_seconds({{Y, M, D}, {H, Mi, S}}) -> days_from_civil(Y, M, D) * 86400 + H * 3600 + Mi * 60 + S.

days_from_civil(Y0, M, D) ->
    Y = case M =< 2 of true -> Y0 - 1; false -> Y0 end,
    Era = floor_div(Y, 400),
    YoE = Y - Era * 400,
    DoY = (153 * (case M > 2 of true -> M - 3; false -> M + 9 end) + 2) div 5 + D - 1,
    DoE = YoE * 365 + YoE div 4 - YoE div 100 + DoY,
    Era * 146097 + DoE - 719468.

civil_from_days(Z0) ->
    Z = Z0 + 719468,
    Era = floor_div(Z, 146097),
    DoE = Z - Era * 146097,
    YoE = (DoE - DoE div 1460 + DoE div 36524 - DoE div 146096) div 365,
    DoY = DoE - (365 * YoE + YoE div 4 - YoE div 100),
    MP = (5 * DoY + 2) div 153,
    D = DoY - (153 * MP + 2) div 5 + 1,
    M = case MP < 10 of true -> MP + 3; false -> MP - 9 end,
    Y = YoE + Era * 400 + (case M =< 2 of true -> 1; false -> 0 end),
    {Y, M, D}.

floor_div(A, B) when A >= 0 -> A div B;
floor_div(A, B) -> -((-A + B - 1) div B).

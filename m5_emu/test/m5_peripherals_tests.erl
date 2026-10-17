-module(m5_peripherals_tests).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    register(m5_emu_test_sink, self()),
    {ok, D} = m5_emu_display:start_link(m5_emu_bridge_test),
    {ok, I} = m5_emu_input:start_link(),
    {D, I}.
cleanup({D, I}) ->
    gen_server:stop(D), gen_server:stop(I),
    catch unregister(m5_emu_test_sink), flush().
flush() -> receive _ -> flush() after 0 -> ok end.
script() -> receive {script, S} -> S after 500 -> timeout end.

periph_test_() -> {foreach, local, fun setup/0, fun cleanup/1, [
    fun(_) -> {"tone is forwarded with volume and is_playing follows the duration", fun() ->
        ?assertNot(m5_speaker:is_playing()),
        ok = m5_speaker:set_volume(100),
        ?assertEqual(100, m5_speaker:get_volume()),
        ?assertEqual(true, m5_speaker:tone(2000, 50)),
        ?assertEqual(<<"m5emu.exec([[\"tone\",2000,50,100]])">>, script()),
        ?assert(m5_speaker:is_playing()),
        timer:sleep(70),
        ?assertNot(m5_speaker:is_playing()) end} end,
    fun(_) -> {"stop forwards", fun() ->
        ?assertEqual(true, m5_speaker:tone(440, 1000, 0, true)), _ = script(),
        ok = m5_speaker:stop(),
        ?assertEqual(<<"m5emu.exec([[\"stop_tone\"]])">>, script()),
        ?assertNot(m5_speaker:is_playing()) end} end,
    fun(_) -> {"play_raw sends base64 samples with rate, stereo, repeat and volume", fun() ->
        ok = m5_speaker:set_volume(80),
        %% 4410 mono u8 samples at 44100 Hz = 100 ms.
        Data = binary:copy(<<128>>, 4410),
        ?assertEqual(true, m5_speaker:play_raw_u8(Data, 44100, false)),
        Expected = iolist_to_binary([<<"m5emu.exec([[\"play_raw\",\"u8\",\"">>, base64:encode(Data),
                                     <<"\",44100,\"false\",1,80]])">>]),
        ?assertEqual(Expected, script()),
        ?assert(m5_speaker:is_playing()),
        timer:sleep(130),
        ?assertNot(m5_speaker:is_playing()),
        %% s16 stereo: 4 bytes per frame; repeat 0 plays until stop/0.
        ?assertEqual(true, m5_speaker:play_raw_s16(<<0:32>>, 8000, true, 0, -1, false)),
        <<"m5emu.exec([[\"play_raw\",\"s16\",\"AAAAAA==\",8000,\"true\",0,80]])">> = script(),
        ?assert(m5_speaker:is_playing()),
        ok = m5_speaker:stop(), _ = script(),
        ?assertNot(m5_speaker:is_playing()),
        ?assertError(badarg, m5_speaker:play_raw_u8(not_a_binary)),
        ?assertError(badarg, m5_speaker:play_raw_s8(<<1>>, 0)) end} end,
    fun(_) -> {"rtc follows the host clock and keeps a set time ticking", fun() ->
        Now = calendar:system_time_to_universal_time(erlang:system_time(second), second),
        ?assert(abs(secs(m5_rtc:get_datetime()) - secs(Now)) =< 1),
        ok = m5_rtc:set_datetime({{2021, 12, 31}, {23, 59, 58}}),
        ?assertEqual({2021, 12, 31}, m5_rtc:get_date()),
        timer:sleep(2100),
        ?assertEqual({2022, 1, 1}, m5_rtc:get_date()),
        ok = m5_rtc:set_date({2024, 2, 29}),
        ?assertEqual({2024, 2, 29}, m5_rtc:get_date()),
        ok = m5_rtc:set_time({12, 34, 56}),
        {{2024, 2, 29}, {12, 34, S}} = m5_rtc:get_datetime(),
        ?assert(S >= 56 andalso S =< 57),
        ?assertError(badarg, m5_rtc:set_datetime(tomorrow)),
        ok = m5_rtc:set_datetime(Now) end} end,
    fun(_) -> {"battery level comes from the input server", fun() ->
        m5_emu_input ! {emscripten, {cast, <<"batt:55">>}}, _ = m5_emu_input:board(),
        ?assertEqual(55, m5_power:get_battery_level()),
        ?assertEqual(false, m5_power:is_charging()),
        ?assertEqual({error, unsupported}, m5_power:deep_sleep()) end} end,
    fun(_) -> {"led pin 19 forwards, others are unsupported", fun() ->
        ok = gpio:set_pin_mode(19, output),
        ok = gpio:digital_write(19, high),
        ?assertEqual(<<"m5emu.exec([[\"led\",\"on\"]])">>, script()),
        ?assertEqual(high, gpio:digital_read(19)),
        ok = gpio:digital_write(19, 0),
        ?assertEqual(<<"m5emu.exec([[\"led\",\"off\"]])">>, script()),
        ?assertEqual(low, gpio:digital_read(19)),
        ?assertEqual({error, unsupported}, gpio:digital_write(2, high)) end} end,
    fun(_) -> {"stubs report enabled flags and types", fun() ->
        ?assert(m5_speaker:is_enabled()),
        ?assert(m5_rtc:is_enabled()), ?assertNot(m5_imu:is_enabled()),
        ?assertEqual(unknown, m5_imu:get_type()), ?assertEqual(unknown, m5_power:get_type()) end} end,
    fun(_) -> {"unsupported functions return an error and log once per function", fun() ->
        Out = capture(fun() ->
            ?assertEqual({error, unsupported}, m5_imu:get_accel()),
            ?assertEqual({error, unsupported}, m5_imu:get_accel()),
            ?assertEqual({error, unsupported}, m5_imu:get_gyro()),
            ?assertEqual({error, unsupported}, m5_display:get_clip_rect()),
            ?assertEqual({error, unsupported}, m5_power_axp192:get_battery_level()),
            ?assertEqual({error, unsupported}, m5_in_i2c:begin_(1, 2, 3)),
            ?assertEqual({error, unsupported}, m5_display:get_raw_color()) end),
        ?assertEqual(1, count(Out, "m5_imu:get_accel/0")),
        ?assertEqual(1, count(Out, "m5_imu:get_gyro/0")),
        ?assertEqual(1, count(Out, "m5_display:get_clip_rect/0")),
        ?assertEqual(1, count(Out, "m5_power_axp192:get_battery_level/0")),
        ?assertEqual(1, count(Out, "m5_in_i2c:begin_/3")),
        ?assertEqual(1, count(Out, "m5_display:get_raw_color/0")) end} end
]}.

%% Run Fun with the group leader replaced by a collector and return what it printed. The log table
%% is dropped first so earlier tests in this VM cannot hide the first-call line.
capture(Fun) ->
    catch ets:delete(m5_emu_unsupported_log),
    Self = self(), Old = group_leader(),
    Collector = spawn_link(fun() -> collect(Self, []) end),
    group_leader(Collector, self()),
    try Fun() after group_leader(Old, self()) end,
    Collector ! {done, Self},
    receive {out, Out} -> lists:flatten(Out) after 1000 -> "" end.
collect(Parent, Acc) ->
    receive
        {io_request, From, Ref, {put_chars, _Enc, Chars}} -> From ! {io_reply, Ref, ok}, collect(Parent, [Acc, Chars]);
        {io_request, From, Ref, {put_chars, _Enc, M, F, A}} -> From ! {io_reply, Ref, ok}, collect(Parent, [Acc, apply(M, F, A)]);
        {done, Parent} -> Parent ! {out, Acc}
    end.
count(Out, Sub) -> length(string:split(lists:flatten(Out), Sub, all)) - 1.
secs(DT) -> calendar:datetime_to_gregorian_seconds(DT).

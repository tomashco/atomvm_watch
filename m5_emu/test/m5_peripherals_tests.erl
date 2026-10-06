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
        ?assertNot(m5_rtc:is_enabled()), ?assertNot(m5_imu:is_enabled()),
        ?assertEqual(unknown, m5_imu:get_type()), ?assertEqual(unknown, m5_power:get_type()) end} end,
    fun(_) -> {"unsupported functions return an error and log once per function", fun() ->
        Out = capture(fun() ->
            ?assertEqual({error, unsupported}, m5_imu:get_accel()),
            ?assertEqual({error, unsupported}, m5_imu:get_accel()),
            ?assertEqual({error, unsupported}, m5_rtc:get_time()),
            ?assertEqual({error, unsupported}, m5_speaker:play_raw_u8(<<>>)),
            ?assertEqual({error, unsupported}, m5_power_axp192:get_battery_level()),
            ?assertEqual({error, unsupported}, m5_in_i2c:begin_(1, 2, 3)),
            ?assertEqual({error, unsupported}, m5_display:get_raw_color()) end),
        ?assertEqual(1, count(Out, "m5_imu:get_accel/0")),
        ?assertEqual(1, count(Out, "m5_rtc:get_time/0")),
        ?assertEqual(1, count(Out, "m5_speaker:play_raw_u8/1")),
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

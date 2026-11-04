-module(m5_scene_input_tests).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    m5_scene_fake_buttons:new(),
    {ok, P} = m5_scene_input:start_link(#{buttons => m5_scene_fake_buttons, poll_ms => infinity}),
    ok = gen_server:call(P, {subscribe_input}),
    P.

cleanup(P) ->
    unlink(P),
    gen_server:stop(P),
    flush().

flush() -> receive _ -> flush() after 0 -> ok end.

events(P) ->
    receive {input_event, P, Ts, E} when is_integer(Ts) -> [E | events(P)] after 0 -> [] end.

poll(P, States) ->
    m5_scene_fake_buttons:set(States),
    ok = m5_scene_input:poll(P),
    events(P).

input_test_() ->
    {foreach, local, fun setup/0, fun cleanup/1, [
        fun(P) -> {"each state gives its event", fun() ->
            ?assertEqual([{button, a, pressed}], poll(P, [{a, was_pressed}])),
            ?assertEqual([{button, b, hold}], poll(P, [{b, was_hold}])),
            ?assertEqual([{button, pwr, released}], poll(P, [{pwr, was_released}])),
            ?assertEqual([{button, a, click}], poll(P, [{a, was_clicked}])),
            ?assertEqual([{button, b, double_click}], poll(P, [{b, was_double_clicked}]))
        end} end,
        fun(P) -> {"events of one poll come in a fixed order", fun() ->
            ?assertEqual([{button, a, released}, {button, a, click}, {button, b, pressed}],
                         poll(P, [{b, was_pressed}, {a, was_clicked}, {a, was_released}]))
        end} end,
        fun(P) -> {"every poll calls update once, no state means no event", fun() ->
            ?assertEqual([], poll(P, [])),
            ?assertEqual([], poll(P, [])),
            ?assertEqual(2, m5_scene_fake_buttons:updates())
        end} end,
        fun(P) -> {"timestamps are system time in milliseconds", fun() ->
            m5_scene_fake_buttons:set([{a, was_pressed}]),
            Before = erlang:system_time(millisecond),
            ok = m5_scene_input:poll(P),
            receive {input_event, P, Ts, _} -> ?assert(Ts >= Before andalso Ts =< Before + 1000) end
        end} end,
        fun(P) -> {"subscribing twice gives one copy of each event", fun() ->
            ok = gen_server:call(P, {subscribe_input}),
            ?assertEqual([{button, a, pressed}], poll(P, [{a, was_pressed}]))
        end} end,
        fun(P) -> {"dead_subscriber_is_removed_test", fun() ->
            Self = self(),
            {Pid, Ref} = spawn_monitor(fun() -> ok = gen_server:call(P, {subscribe_input}), Self ! subscribed end),
            receive subscribed -> ok end,
            receive {'DOWN', Ref, process, Pid, _} -> ok end,
            ?assertEqual([{button, a, pressed}], poll(P, [{a, was_pressed}])),
            #{subs := Subs} = sys:get_state(P),
            ?assertEqual([Self], [S || {S, _} <- Subs])
        end} end
    ]}.

%% Reading every flag of every button on each poll cost a few milliseconds every 10 ms on the watch:
%% a button's flags are read only for active_ms after its last change.
active_window_test_() ->
    {setup,
     fun() ->
         m5_scene_fake_buttons:new(),
         {ok, P} = m5_scene_input:start_link(#{buttons => m5_scene_fake_buttons, poll_ms => infinity,
                                               active_ms => 100}),
         P
     end,
     fun cleanup/1,
     fun(P) -> fun() ->
         ok = gen_server:call(P, {subscribe_input}),
         %% Every button is read for active_ms after start, then not any more.
         poll_flags(P, []),
         ?assertEqual(15, m5_scene_fake_buttons:reads()),
         timer:sleep(150),
         ?assertEqual([], poll_flags(P, [{b, was_hold}])),
         ?assertEqual(15, m5_scene_fake_buttons:reads()),
         %% A press is read, and a hold flag set later, without a change, still is.
         ?assertEqual([{button, a, pressed}], poll(P, [{a, was_pressed}])),
         ?assertEqual([{button, a, hold}], poll_flags(P, [{a, was_hold}])),
         %% Only the changed button is read: 5 flags per poll.
         Reads = m5_scene_fake_buttons:reads(),
         poll_flags(P, []),
         ?assertEqual(Reads + 5, m5_scene_fake_buttons:reads()),
         %% After active_ms without a change, it is not read any more.
         timer:sleep(150),
         Reads1 = m5_scene_fake_buttons:reads(),
         ?assertEqual([], poll_flags(P, [{a, was_hold}])),
         ?assertEqual(Reads1, m5_scene_fake_buttons:reads())
     end end}.

poll_flags(P, States) ->
    m5_scene_fake_buttons:set_flags(States),
    ok = m5_scene_input:poll(P),
    events(P).

timer_polls_by_itself_test() ->
    m5_scene_fake_buttons:new(),
    m5_scene_fake_buttons:set([{pwr, was_pressed}]),
    {ok, P} = m5_scene_input:start_link(#{buttons => m5_scene_fake_buttons, poll_ms => 5}),
    ok = gen_server:call(P, {subscribe_input}),
    receive {input_event, P, _, E} -> ?assertEqual({button, pwr, pressed}, E)
    after 1000 -> ?assert(false)
    end,
    unlink(P),
    gen_server:stop(P).

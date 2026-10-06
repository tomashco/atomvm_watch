-module(m5_tests).
-include_lib("eunit/include/eunit.hrl").

%% The mock bridge must answer m5emu.boardReady() the way the page does.
responder() ->
    receive {script, <<"m5emu.boardReady()">>} ->
        m5_emu_input ! {emscripten, {cast, <<"board:stick_cplus2:135:240">>}}, responder();
            {script, _} -> responder();
            stop -> ok
    end.

begin_test() ->
    Resp = spawn_link(fun responder/0), register(m5_emu_test_sink, Resp),
    ok = m5:begin_([{bridge, m5_emu_bridge_test}]),
    ?assertEqual(stick_cplus2, m5:get_board()),
    ?assertEqual(135, m5_display:width()),
    ?assertEqual(240, m5_display:height()),
    ok = m5:update(),
    ?assertNot(m5_btn_a:was_pressed()),
    ?assertEqual(10, m5_btn_a:get_debounce_thresh()),
    %% begin_ twice is allowed and resets state
    ok = m5_display:set_rotation(1),
    ok = m5:begin_([{bridge, m5_emu_bridge_test}]),
    ?assertEqual(0, m5_display:get_rotation()),
    Resp ! stop,
    gen_server:stop(m5_emu_input),
    gen_server:stop(m5_emu_display).

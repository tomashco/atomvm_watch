-module(m5_emu_display_tests).
-include_lib("eunit/include/eunit.hrl").

%% With {foreach, local, ...} setup and the tests run in the same process, so the sink
%% registered here is the process that receives the scripts.
setup() ->
    register(m5_emu_test_sink, self()),
    {ok, Pid} = m5_emu_display:start_link(m5_emu_bridge_test),
    ok = m5_emu_display:configure(135, 240),
    Pid.
cleanup(Pid) -> gen_server:stop(Pid), catch unregister(m5_emu_test_sink), flush().
flush() -> receive _ -> flush() after 0 -> ok end.
script() -> receive {script, S} -> S after 500 -> timeout end.

display_test_() -> {foreach, local, fun setup/0, fun cleanup/1, [
    fun(_) -> {"immediate flush outside a batch", fun() ->
        ok = m5_display:fill_rect(1, 2, 3, 4, 16#00FF00),
        ?assertEqual(<<"m5emu.exec([[\"fill_rect\",1,2,3,4,65280]])">>, script()) end} end,
    fun(_) -> {"batched flush", fun() ->
        ok = m5_display:start_write(),
        ok = m5_display:fill_rect(0, 0, 1, 1, 0),
        ok = m5_display:draw_pixel(5, 5, 16#FFFFFF),
        ?assertEqual(timeout, script()),
        ok = m5_display:end_write(),
        ?assertEqual(<<"m5emu.exec([[\"fill_rect\",0,0,1,1,0],[\"draw_pixel\",5,5,16777215]])">>, script()) end} end,
    fun(_) -> {"width and height follow rotation", fun() ->
        ?assertEqual(135, m5_display:width()), ?assertEqual(240, m5_display:height()),
        ok = m5_display:set_rotation(1),
        ?assertEqual(<<"m5emu.exec([[\"set_rotation\",1]])">>, script()),
        ?assertEqual(240, m5_display:width()), ?assertEqual(135, m5_display:height()),
        ?assertEqual(1, m5_display:get_rotation()) end} end,
    fun(_) -> {"current color is used by 4-arity fill_rect", fun() ->
        ok = m5_display:set_color({rgb, {0, 0, 255}}),
        ?assertEqual(<<"m5emu.exec([[\"set_color\",255]])">>, script()),
        ok = m5_display:fill_rect(0, 0, 2, 2),
        ?assertEqual(<<"m5emu.exec([[\"fill_rect\",0,0,2,2,255]])">>, script()) end} end,
    fun(_) -> {"cursor and text size are tracked and sent", fun() ->
        ok = m5_display:set_cursor(10, 20), _ = script(),
        ?assertEqual({10, 20}, m5_display:get_cursor()),
        ok = m5_display:set_text_size(2), _ = script(),
        ?assertEqual(16, m5_display:font_height()), ?assertEqual(12, m5_display:font_width()),
        ?assertEqual(5, m5_display:print(<<"hello">>)),
        ?assertEqual(<<"m5emu.exec([[\"print\",\"hello\"]])">>, script()),
        ?assertEqual({10 + 5 * 12, 20}, m5_display:get_cursor()),
        ?assertEqual(1, m5_display:println()),
        ?assertEqual({0, 36}, m5_display:get_cursor()) end} end,
    fun(_) -> {"cursor uses the renderer's rounded text size", fun() ->
        ok = m5_display:set_cursor(0, 0), ok = m5_display:set_text_size(1.5), _ = script(),
        _ = m5_display:print(<<"ab">>), _ = script(),
        ?assertEqual({24, 0}, m5_display:get_cursor()),   %% size 1.5 rounds to 2: 2 * 12
        ?assertEqual(1, m5_display:println()),
        ?assertEqual({0, 16}, m5_display:get_cursor()) end} end,
    fun(_) -> {"print wraps at the right edge", fun() ->
        %% width 135, size 1: 22 chars fit (132 px); the 23rd wraps to the next line.
        ok = m5_display:set_cursor(0, 0), _ = script(),
        _ = m5_display:print(binary:copy(<<"x">>, 23)), _ = script(),
        ?assertEqual({6, 8}, m5_display:get_cursor()) end} end,
    fun(_) -> {"cursor advance counts code points, not bytes", fun() ->
        ok = m5_display:set_cursor(0, 0), _ = script(),
        _ = m5_display:print(<<"é"/utf8>>), _ = script(),
        ?assertEqual({6, 0}, m5_display:get_cursor()) end} end,
    fun(_) -> {"nested start_write keeps buffered commands", fun() ->
        ok = m5_display:start_write(),
        ok = m5_display:fill_rect(0, 0, 1, 1, 0),
        ok = m5_display:start_write(),
        ok = m5_display:draw_pixel(5, 5, 1),
        ok = m5_display:end_write(),
        ?assertEqual(timeout, script()),
        ok = m5_display:end_write(),
        ?assertEqual(<<"m5emu.exec([[\"fill_rect\",0,0,1,1,0],[\"draw_pixel\",5,5,1]])">>, script()),
        ok = m5_display:end_write(),
        ?assertEqual(timeout, script()) end} end,
    fun(_) -> {"invalid utf-8 does not crash the server", fun() ->
        Pid = whereis(m5_emu_display),
        ok = m5_display:set_cursor(0, 0), _ = script(),
        ?assertEqual(2, m5_display:print(<<255, 254>>)), _ = script(),
        ?assertEqual({12, 0}, m5_display:get_cursor()),
        ?assertEqual(Pid, whereis(m5_emu_display)),
        ?assertEqual(6, m5_display:draw_string(<<"é"/utf8>>, 0, 0)) end} end,
    fun(_) -> {"unsupported functions return an error tuple", fun() ->
        ?assertEqual({error, unsupported}, m5_display:set_scroll_rect(0, 0, 1, 1)),
        ?assertEqual(ok, m5_display:set_epd_mode(fastest)) end} end
]}.

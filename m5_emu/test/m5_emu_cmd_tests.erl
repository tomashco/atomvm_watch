-module(m5_emu_cmd_tests).
-include_lib("eunit/include/eunit.hrl").

encode_test() ->
    Json = iolist_to_binary(m5_emu_cmd:encode([{fill_rect, 0, 0, 10, 20, 16#FF0000}, {print, <<"Hi \"there\"\n">>}])),
    ?assertEqual(<<"[[\"fill_rect\",0,0,10,20,16711680],[\"print\",\"Hi \\\"there\\\"\\n\"]]">>, Json).

exec_script_test() ->
    ?assertEqual(<<"m5emu.exec([[\"sleep\"]])">>, iolist_to_binary(m5_emu_cmd:exec_script([{sleep}]))).

batch_script_test() ->
    Cmds = [{fill_rect, 0, 0, 10, 20, 16#FF0000}, {print, <<"a", 1, "b">>}, {sleep}],
    Batch = lists:foldl(fun(C, B) -> m5_emu_cmd:batch_append(B, C) end, <<>>, Cmds),
    ?assertEqual(iolist_to_binary(m5_emu_cmd:exec_script(Cmds)),
                 iolist_to_binary(m5_emu_cmd:batch_script(Batch))).

negative_and_float_test() ->
    ?assertEqual(<<"[[\"set_text_size\",-1,2.5]]">>, iolist_to_binary(m5_emu_cmd:encode([{set_text_size, -1, 2.5}]))).

color_test() ->
    ?assertEqual(16#FF0000, m5_emu_cmd:to_rgb888(16#FF0000)),
    ?assertEqual(16#FF0000, m5_emu_cmd:to_rgb888({rgb888, 16#FF0000})),
    ?assertEqual(16#FF0000, m5_emu_cmd:to_rgb888({rgb, {255, 0, 0}})),
    %% RGB565 0xF800 is pure red; low bits are replicated so 0x1F -> 0xFF.
    ?assertEqual(16#FF0000, m5_emu_cmd:to_rgb888({rgb565, 16#F800})),
    ?assertEqual(16#00FF00, m5_emu_cmd:to_rgb888({rgb565, 16#07E0})),
    ?assertEqual(16#0000FF, m5_emu_cmd:to_rgb888({rgb565, 16#001F})).

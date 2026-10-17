-module(m5_emu_input_tests).
-include_lib("eunit/include/eunit.hrl").

setup() -> {ok, Pid} = m5_emu_input:start_link(), Pid.
cleanup(Pid) -> gen_server:stop(Pid).
%% board() is a sync call, so the cast is processed before it returns.
cast(Bin) -> m5_emu_input ! {emscripten, {cast, Bin}}, m5_emu_input:board().

input_test_() -> {foreach, local, fun setup/0, fun cleanup/1, [
    fun(_) -> {"fresh state", fun() ->
        ok = m5_emu_input:update(),
        ?assertNot(m5_emu_input:btn(a, was_pressed)),
        ?assert(m5_emu_input:btn(a, is_released)),
        ?assertEqual(100, m5_emu_input:battery()) end} end,
    fun(_) -> {"board handshake", fun() ->
        ?assertEqual({error, timeout}, m5_emu_input:await_board(20)),
        cast(<<"board:stick_cplus2:135:240">>),
        ?assertEqual({ok, {stick_cplus2, 135, 240}}, m5_emu_input:await_board(20)),
        ?assertEqual(stick_cplus2, m5_emu_input:board()) end} end,
    fun(_) -> {"button press shows up after update", fun() ->
        m5_emu_input:btn_set(a, set_debounce_thresh, 0),
        cast(<<"a:down">>),
        ok = m5_emu_input:update(),
        ?assert(m5_emu_input:btn(a, is_pressed)),
        ?assert(m5_emu_input:btn(a, was_pressed)),
        ok = m5_emu_input:update(),
        ?assertNot(m5_emu_input:btn(a, was_pressed)),
        cast(<<"a:up">>),
        ok = m5_emu_input:update(),
        ?assert(m5_emu_input:btn(a, was_released)),
        ?assertNot(m5_emu_input:btn(b, was_released)) end} end,
    fun(_) -> {"down then up between updates still yields one press (latch)", fun() ->
        m5_emu_input:btn_set(a, set_debounce_thresh, 0),
        cast(<<"a:down">>),
        cast(<<"a:up">>),
        ok = m5_emu_input:update(),
        ?assert(m5_emu_input:btn(a, was_pressed)),
        ?assert(m5_emu_input:btn(a, is_pressed)),
        ok = m5_emu_input:update(),
        ?assertNot(m5_emu_input:btn(a, was_pressed)),
        ?assert(m5_emu_input:btn(a, was_released)),
        ?assert(m5_emu_input:btn(a, is_released)),
        ok = m5_emu_input:update(),
        ?assertNot(m5_emu_input:btn(a, was_released)) end} end,
    fun(_) -> {"c and ext never press, unknown names ignored", fun() ->
        cast(<<"c:down">>), cast(<<"ext:down">>), cast(<<"x:down">>),
        ok = m5_emu_input:update(),
        ?assertNot(m5_emu_input:btn(c, is_pressed)),
        ?assertNot(m5_emu_input:btn(ext, is_pressed)) end} end,
    fun(_) -> {"battery and unknown messages", fun() ->
        cast(<<"batt:42">>), ?assertEqual(42, m5_emu_input:battery()),
        cast(<<"garbage">>), ?assertEqual(42, m5_emu_input:battery()) end} end
]}.

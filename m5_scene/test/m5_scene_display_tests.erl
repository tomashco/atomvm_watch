-module(m5_scene_display_tests).
-include_lib("eunit/include/eunit.hrl").

-define(BG, 16#101010).

setup() ->
    register(m5_scene_test_sink, self()),
    {ok, Pid} = m5_scene_display:start_link(#{display => m5_scene_fake_display, width => 240,
                                               height => 135, background => ?BG}),
    Pid.

cleanup(Pid) ->
    unlink(Pid),
    gen_server:stop(Pid),
    unregister(m5_scene_test_sink),
    _ = m5_scene_fake_display:calls(),
    ok.

calls() -> m5_scene_fake_display:calls().
update(Pid, List) -> m5_scene_display:call(Pid, {update, List}).

display_test_() ->
    {foreach, local, fun setup/0, fun cleanup/1, [
        fun(P) -> {"a frame becomes display calls", fun() ->
            ?assertEqual(ok, update(P, [{rect, 1, 1, 2, 2, 16#FF0000}])),
            ?assertEqual([{start_write, []}, {fill_rect, [0, 0, 240, 135, ?BG]},
                          {fill_rect, [1, 1, 2, 2, 16#FF0000]}, {end_write, []}], calls())
        end} end,
        fun(P) -> {"the same frame again draws nothing", fun() ->
            L = [{rect, 1, 1, 2, 2, 16#FF0000}],
            ok = update(P, L), _ = calls(),
            ok = update(P, L),
            ?assertEqual([], calls())
        end} end,
        fun(P) -> {"improper_list_keeps_last_frame_test", fun() ->
            L = [{rect, 1, 1, 2, 2, 16#FF0000}],
            ok = update(P, L), _ = calls(),
            ?assertEqual({error, invalid_display_list}, update(P, [{rect, 0, 0, 1, 1, 0} | bad])),
            ?assertEqual([], calls()),
            %% Still diffed against the last good frame.
            ok = update(P, L),
            ?assertEqual([], calls())
        end} end,
        fun(P) -> {"invalid items are skipped, the rest is drawn", fun() ->
            ?assertEqual(ok, update(P, [garbage, {rect, 1, 1, 2, 2, 5}])),
            ?assertEqual([{start_write, []}, {fill_rect, [0, 0, 240, 135, ?BG]},
                          {fill_rect, [1, 1, 2, 2, 5]}, {end_write, []}], calls())
        end} end,
        fun(P) -> {"unknown calls get an error, the server lives", fun() ->
            ?assertEqual({error, unknown_call}, gen_server:call(P, hello)),
            ?assertEqual(ok, update(P, []))
        end} end
    ]}.

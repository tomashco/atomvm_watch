-module(m5_scene_tests).
-include_lib("eunit/include/eunit.hrl").

%% catch: a test that failed earlier in this process may have left the name registered.
sink() ->
    catch unregister(m5_scene_test_sink),
    register(m5_scene_test_sink, self()).

opts(Extra) ->
    Extra ++ [{display_module, m5_scene_fake_display}, {buttons_module, m5_scene_fake_buttons},
              {poll_ms, infinity}].

start_link_sets_rotation_and_background_test() ->
    sink(),
    m5_scene_fake_buttons:new(),
    {ok, Opts} = m5_scene:start_link(opts([{rotation, 3}, {background, 16#123456}])),
    ?assertMatch([{display_server, {m5_scene_display, _}}, {input_server, _}], Opts),
    ?assertEqual([{set_rotation, [3]}], m5_scene_fake_display:calls()),
    {m5_scene_display, D} = proplists:get_value(display_server, Opts),
    ok = m5_scene_display:call(D, {update, []}),
    ?assertEqual([{start_write, []}, {fill_rect, [0, 0, 240, 135, 16#123456]}, {end_write, []}],
                 m5_scene_fake_display:calls()),
    unregister(m5_scene_test_sink).

defaults_are_landscape_and_black_test() ->
    sink(),
    m5_scene_fake_buttons:new(),
    {ok, Opts} = m5_scene:start_link(opts([])),
    ?assertEqual([{set_rotation, [1]}], m5_scene_fake_display:calls()),
    {m5_scene_display, D} = proplists:get_value(display_server, Opts),
    ok = m5_scene_display:call(D, {update, []}),
    ?assertMatch([_, {fill_rect, [0, 0, 240, 135, 0]}, _], m5_scene_fake_display:calls()),
    unregister(m5_scene_test_sink).

avm_scene_draws_and_receives_input_through_m5_scene_test() ->
    sink(),
    m5_scene_fake_buttons:new(),
    {ok, Opts} = m5_scene:start_link(opts([])),
    _ = m5_scene_fake_display:calls(),
    {ok, _Scene} = avm_scene:start_link(m5_scene_test_scene, self(), Opts),
    ?assertEqual([{start_write, []}, {fill_rect, [0, 0, 240, 135, 0]},
                  {fill_rect, [0, 0, 10, 10, 16#FF0000]}, {end_write, []}],
                 m5_scene_fake_display:frame()),
    m5_scene_fake_buttons:set([{a, was_pressed}]),
    ok = m5_scene_input:poll(proplists:get_value(input_server, Opts)),
    receive {scene_input, E} -> ?assertEqual({button, a, pressed}, E) after 1000 -> ?assert(false) end,
    ?assertEqual([{start_write, []}, {set_clip_rect, [0, 0, 10, 10]}, {fill_rect, [0, 0, 10, 10, 0]},
                  {fill_rect, [0, 0, 10, 10, 16#00FF00]}, {clear_clip_rect, []}, {end_write, []}],
                 m5_scene_fake_display:frame()),
    unregister(m5_scene_test_sink).

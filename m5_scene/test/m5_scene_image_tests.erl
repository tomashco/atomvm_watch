-module(m5_scene_image_tests).
-include_lib("eunit/include/eunit.hrl").

v(Item) -> {ok, [I], _} = m5_scene_render:validate([Item]), I.

rgb565_test() ->
    ?assertEqual(<<16#F8, 16#00>>, m5_scene_image:rgb565(255, 0, 0)),
    ?assertEqual(<<16#07, 16#E0>>, m5_scene_image:rgb565(0, 255, 0)),
    ?assertEqual(<<16#00, 16#1F>>, m5_scene_image:rgb565(0, 0, 255)),
    ?assertEqual(<<16#FF, 16#FF>>, m5_scene_image:rgb565(255, 255, 255)).

blend_test() ->
    ?assertEqual(255, m5_scene_image:blend(255, 255, 0)),
    ?assertEqual(7, m5_scene_image:blend(255, 0, 7)),
    ?assertEqual(128, m5_scene_image:blend(255, 128, 0)).

opaque_image_blends_against_background_test() ->
    %% 2x1 over blue: opaque red, then green at alpha 128.
    Img = {image, 3, 4, 16#0000FF, {rgba8888, 2, 1, <<255, 0, 0, 255, 0, 255, 0, 128>>}},
    {Ops, _} = m5_scene_image:ops(v(Img), #{}),
    G = m5_scene_image:rgb565(0, 128, 127),
    ?assertEqual([{push_image, [3, 4, 2, 1, <<16#F8, 16#00, G/binary>>]}], Ops).

transparent_image_pushes_opaque_runs_test() ->
    %% 4x2. Row 0: red, red, alpha 127, red. Row 1: all alpha 0.
    R = <<255, 0, 0, 255>>, Half = <<255, 0, 0, 127>>, T = <<0, 0, 0, 0>>,
    Px = <<R/binary, R/binary, Half/binary, R/binary, T/binary, T/binary, T/binary, T/binary>>,
    {Ops, _} = m5_scene_image:ops(v({image, 10, 20, transparent, {rgba8888, 4, 2, Px}}), #{}),
    ?assertEqual([{push_image, [10, 20, 2, 1, <<16#F8, 0, 16#F8, 0>>]},
                  {push_image, [13, 20, 1, 1, <<16#F8, 0>>]}], Ops).

alpha_128_is_drawn_when_transparent_test() ->
    {Ops, _} = m5_scene_image:ops(v({image, 0, 0, transparent, {rgba8888, 1, 1, <<0, 0, 255, 128>>}}), #{}),
    ?assertEqual([{push_image, [0, 0, 1, 1, <<16#00, 16#1F>>]}], Ops).

cache_reuses_conversion_test() ->
    I = v({image, 0, 0, 0, {rgba8888, 1, 1, <<1, 2, 3, 255>>}}),
    {_, C1} = m5_scene_image:ops(I, #{}),
    ?assertEqual(1, map_size(C1)),
    %% Replace the entry with a sentinel: the next call must use it instead of converting again.
    [Key] = maps:keys(C1),
    {Ops, _} = m5_scene_image:ops(I, C1#{Key := {[{0, 0, 1, 1, <<"cached">>}], 6, 0}}),
    ?assertEqual([{push_image, [0, 0, 1, 1, <<"cached">>]}], Ops).

moved_image_shares_the_cache_entry_test() ->
    Img = {rgba8888, 1, 1, <<1, 2, 3, 255>>},
    {_, C1} = m5_scene_image:ops(v({image, 0, 0, 0, Img}), #{}),
    {Ops, C2} = m5_scene_image:ops(v({image, 50, 60, 0, Img}), C1),
    ?assertEqual(C1, C2),
    ?assertMatch([{push_image, [50, 60, 1, 1, _]}], Ops).

retain_with_no_budget_keeps_only_listed_images_test() ->
    A = v({image, 0, 0, 0, {rgba8888, 1, 1, <<1, 2, 3, 255>>}}),
    B = v({image, 0, 0, 0, {rgba8888, 1, 1, <<4, 5, 6, 255>>}}),
    {_, C1} = m5_scene_image:ops(A, #{}),
    {_, C2} = m5_scene_image:ops(B, C1),
    ?assertEqual(2, map_size(C2)),
    ?assertEqual(C1, m5_scene_image:retain(C2, [A], 0)).

%% An animation alternates between frames: the frame not shown must stay converted.
retain_keeps_a_dropped_image_within_the_budget_test() ->
    A = v({image, 0, 0, 0, {rgba8888, 1, 1, <<1, 2, 3, 255>>}}),
    B = v({image, 0, 0, 0, {rgba8888, 1, 1, <<4, 5, 6, 255>>}}),
    {_, C1} = m5_scene_image:ops(A, #{}),
    {_, C2} = m5_scene_image:ops(B, C1),
    C3 = m5_scene_image:retain(C2, [A]),
    ?assertEqual(2, map_size(C3)),
    %% B is still cached: drawing it again uses the entry (sentinel) instead of converting.
    [KB] = maps:keys(C3) -- maps:keys(C1),
    {Ops, _} = m5_scene_image:ops(B, C3#{KB := {[{0, 0, 1, 1, <<"cached">>}], 6, 0}}),
    ?assertEqual([{push_image, [0, 0, 1, 1, <<"cached">>]}], Ops).

%% Dropped images are kept most recently used first, up to the budget in bytes of RGB565 data.
retain_drops_the_least_recently_used_beyond_the_budget_test() ->
    [A, B, C] = [v({image, 0, 0, 0, {rgba8888, 1, 1, <<N, 0, 0, 255>>}}) || N <- [1, 2, 3]],
    {_, C1} = m5_scene_image:ops(A, #{}),
    C2 = m5_scene_image:retain(C1, [A], 2),           % frame 1 shows A
    {_, C3} = m5_scene_image:ops(B, C2),
    C4 = m5_scene_image:retain(C3, [B], 2),           % frame 2 shows B; A kept (2 bytes)
    ?assertEqual(2, map_size(C4)),
    {_, C5} = m5_scene_image:ops(C, C4),
    C6 = m5_scene_image:retain(C5, [C], 2),           % frame 3 shows C; only B fits the budget
    {_, OnlyB} = m5_scene_image:ops(B, m5_scene_image:retain(C5, [C], 0)),
    ?assertEqual(lists:sort(maps:keys(OnlyB)), lists:sort(maps:keys(C6))).

scaled_image_samples_the_source_test() ->
    %% Source 2x1: red, green. Scale 2 gives 4x2: R R G G on both rows.
    Px = <<255, 0, 0, 255, 0, 255, 0, 255>>,
    Row = <<16#F8, 0, 16#F8, 0, 16#07, 16#E0, 16#07, 16#E0>>,
    I = v({scaled_cropped_image, 0, 0, 4, 2, 0, 0, 0, 2, 2, [], {rgba8888, 2, 1, Px}}),
    {Ops, _} = m5_scene_image:ops(I, #{}),
    ?assertEqual([{push_image, [0, 0, 4, 2, <<Row/binary, Row/binary>>]}], Ops).

scaled_image_flip_x_mirrors_the_drawn_pixels_test() ->
    Px = <<255, 0, 0, 255, 0, 255, 0, 255>>,
    Row = <<16#07, 16#E0, 16#07, 16#E0, 16#F8, 0, 16#F8, 0>>,
    I = v({scaled_cropped_image, 0, 0, 4, 1, 0, 0, 0, 2, 1, [flip_x], {rgba8888, 2, 1, Px}}),
    {Ops, _} = m5_scene_image:ops(I, #{}),
    ?assertEqual([{push_image, [0, 0, 4, 1, Row]}], Ops).

%% A full-screen image must convert in a heap far smaller than a per-pixel list would need (the
%% watch has no PSRAM). The cap is about 0.5 MB on 64-bit; a list with one binary per pixel needs
%% several times that for 240x135.
large_image_converts_in_bounded_heap_test_() ->
    {timeout, 30, fun() ->
        W = 240, H = 135,
        Px = binary:copy(<<255, 0, 0, 255>>, W * H),
        Opaque = v({image, 0, 0, 0, {rgba8888, W, H, Px}}),
        Transparent = v({image, 0, 0, transparent, {rgba8888, W, H, Px}}),
        Red = binary:copy(<<16#F8, 0>>, W * H),
        ?assertEqual({ok, [{push_image, [0, 0, W, H, Red]}]}, bounded(fun() -> ops_only(Opaque) end)),
        {ok, Runs} = bounded(fun() -> ops_only(Transparent) end),
        ?assertEqual(H, length(Runs))
    end}.

ops_only(Item) -> {Ops, _} = m5_scene_image:ops(Item, #{}), Ops.

bounded(Fun) ->
    Self = self(),
    {Pid, Ref} = spawn_opt(fun() -> Self ! {self(), Fun()} end,
                           [monitor, {max_heap_size, #{size => 65536, kill => true, error_logger => false}}]),
    receive
        {Pid, Result} -> erlang:demonitor(Ref, [flush]), {ok, Result};
        {'DOWN', Ref, process, Pid, Reason} -> {error, Reason}
    end.

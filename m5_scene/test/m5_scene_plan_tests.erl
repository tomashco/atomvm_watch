-module(m5_scene_plan_tests).
-include_lib("eunit/include/eunit.hrl").

-define(S, {240, 135, 0}).

v(L) -> {ok, I, _} = m5_scene_render:validate(L), I.
first(New) -> {Ops, _} = m5_scene_render:plan(none, v(New), ?S, #{}), Ops.
next(Old, New) -> {Ops, _} = m5_scene_render:plan(v(Old), v(New), ?S, #{}), Ops.

first_frame_is_full_redraw_back_to_front_test() ->
    ?assertEqual([{start_write, []}, {fill_rect, [0, 0, 240, 135, 0]},
                  {fill_rect, [0, 0, 10, 10, 2]}, {fill_rect, [5, 5, 10, 10, 1]},
                  {end_write, []}],
                 first([{rect, 5, 5, 10, 10, 1}, {rect, 0, 0, 10, 10, 2}])).

empty_first_frame_clears_the_screen_test() ->
    ?assertEqual([{start_write, []}, {fill_rect, [0, 0, 240, 135, 0]}, {end_write, []}], first([])).

unchanged_frame_draws_nothing_test() ->
    L = [{rect, 5, 5, 10, 10, 1}, {text, 0, 0, default16px, 1, 0, "x"}],
    ?assertEqual([], next(L, L)).

moved_item_redraws_its_old_and_new_area_test() ->
    Under = {rect, 0, 0, 50, 50, 9},
    ?assertEqual([{start_write, []},
                  {set_clip_rect, [10, 10, 5, 5]}, {fill_rect, [10, 10, 5, 5, 0]},
                  {fill_rect, [0, 0, 50, 50, 9]}, {clear_clip_rect, []},
                  {set_clip_rect, [30, 10, 5, 5]}, {fill_rect, [30, 10, 5, 5, 0]},
                  {fill_rect, [0, 0, 50, 50, 9]}, {fill_rect, [30, 10, 5, 5, 1]},
                  {clear_clip_rect, []},
                  {end_write, []}],
                 next([{rect, 10, 10, 5, 5, 1}, Under], [{rect, 30, 10, 5, 5, 1}, Under])).

overlapping_dirty_rects_are_merged_test() ->
    ?assertEqual([{start_write, []},
                  {set_clip_rect, [0, 0, 15, 15]}, {fill_rect, [0, 0, 15, 15, 0]},
                  {fill_rect, [5, 5, 10, 10, 1]}, {clear_clip_rect, []},
                  {end_write, []}],
                 next([{rect, 0, 0, 10, 10, 1}], [{rect, 5, 5, 10, 10, 1}])).

removed_item_is_cleared_test() ->
    ?assertEqual([{start_write, []}, {set_clip_rect, [1, 1, 2, 2]}, {fill_rect, [1, 1, 2, 2, 0]},
                  {clear_clip_rect, []}, {end_write, []}],
                 next([{rect, 1, 1, 2, 2, 1}], [])).

dirty_rect_is_clipped_to_the_screen_test() ->
    ?assertMatch([{start_write, []}, {set_clip_rect, [230, 130, 10, 5]} | _],
                 next([], [{rect, 230, 130, 20, 20, 1}])).

large_change_is_full_redraw_test() ->
    %% 200 x 100 = 20000 px, over half of 240 x 135 = 16200.
    ?assertEqual([{start_write, []}, {fill_rect, [0, 0, 240, 135, 0]},
                  {fill_rect, [0, 0, 200, 100, 1]}, {end_write, []}],
                 next([], [{rect, 0, 0, 200, 100, 1}])).

change_under_half_is_partial_test() ->
    ?assertMatch([{start_write, []}, {set_clip_rect, [0, 0, 100, 100]} | _],
                 next([], [{rect, 0, 0, 100, 100, 1}])).

reordered_list_is_full_redraw_test() ->
    A = {rect, 0, 0, 10, 10, 1},
    B = {rect, 5, 5, 10, 10, 2},
    ?assertEqual([{start_write, []}, {fill_rect, [0, 0, 240, 135, 0]},
                  {fill_rect, [5, 5, 10, 10, 2]}, {fill_rect, [0, 0, 10, 10, 1]},
                  {end_write, []}],
                 next([B, A], [A, B])).

reorder_with_another_change_is_full_redraw_test() ->
    %% A and B overlap and swap stacking order while X, elsewhere, changes colour: redrawing only
    %% X's box would leave A on top of B.
    A = {rect, 0, 0, 10, 10, 1},
    B = {rect, 5, 5, 10, 10, 2},
    ?assertMatch([{start_write, []}, {fill_rect, [0, 0, 240, 135, 0]} | _],
                 next([A, B, {rect, 200, 0, 10, 10, 3}], [B, A, {rect, 200, 0, 10, 10, 4}])).

offscreen_change_draws_nothing_test() ->
    ?assertEqual([], next([{rect, 300, 0, 5, 5, 1}], [{rect, 400, 0, 5, 5, 1}])).

empty_rect_draws_nothing_test() ->
    ?assertEqual([{start_write, []}, {fill_rect, [0, 0, 240, 135, 0]}, {end_write, []}],
                 first([{rect, 0, 0, 0, 5, 1}])).

text_ops_test() ->
    %% Opaque background: a filled box, then transparent text (Fg = Bg in set_text_color), so text
    %% whose Fg equals its Bg still covers its box.
    ?assertEqual([{start_write, []}, {fill_rect, [0, 0, 240, 135, 0]},
                  {fill_rect, [4, 5, 24, 16, 16#FFFFFF]},
                  {set_text_size, [2]}, {set_text_color, [16#FFFFFF, 16#FFFFFF]},
                  {draw_string, [<<"ab">>, 4, 5]},
                  {set_text_size, [1]}, {set_text_color, [1, 1]}, {draw_string, [<<"c">>, 0, 0]},
                  {end_write, []}],
                 first([{text, 0, 0, m5_font1, 1, transparent, "c"},
                        {text, 4, 5, default16px, 16#FFFFFF, 16#FFFFFF, "ab"}])).

shape_ops_test() ->
    Ops = first([{line, 0, 0, 9, 0, 1, 5}, {circle, 10, 10, 3, 4}, {ellipse, 10, 10, 3, 4, 6},
                 {rounded_rect, 0, 0, 12, 20, 3, 7}]),
    ?assertEqual([{fill_round_rect, [0, 0, 12, 20, 3, 7]}, {fill_ellipse, [10, 10, 3, 4, 6]},
                  {fill_circle, [10, 10, 3, 4]}, {draw_line, [0, 0, 9, 0, 5]}],
                 lists:sublist(Ops, 3, 4)).

thick_line_is_two_triangles_and_caps_test() ->
    Ops = first([{line, 0, 10, 20, 10, 3, 5}]),
    ?assertEqual([{fill_triangle, [0, 11, 20, 11, 20, 9, 5]},
                  {fill_triangle, [0, 11, 20, 9, 0, 9, 5]},
                  {fill_circle, [0, 10, 1, 5]}, {fill_circle, [20, 10, 1, 5]}],
                 lists:sublist(Ops, 3, 4)).

image_ops_come_from_m5_scene_image_test() ->
    ?assertMatch([_, _, {push_image, [3, 4, 1, 1, <<16#F8, 0>>]}, {end_write, []}],
                 first([{image, 3, 4, 0, {rgba8888, 1, 1, <<255, 0, 0, 255>>}}])).

plan_keeps_a_dropped_image_cached_test() ->
    Img = {image, 0, 0, 0, {rgba8888, 1, 1, <<1, 2, 3, 255>>}},
    {_, C1} = m5_scene_render:plan(none, v([Img]), ?S, #{}),
    ?assertEqual(1, map_size(C1)),
    {_, C2} = m5_scene_render:plan(v([Img]), v([]), ?S, C1),
    ?assertEqual(1, map_size(C2)).

%% Two animation frames shown in turn are each converted once.
plan_alternating_frames_keeps_both_cached_test() ->
    A = {image, 0, 0, transparent, {rgba8888, 1, 1, <<1, 2, 3, 255>>}},
    B = {image, 0, 0, transparent, {rgba8888, 1, 1, <<4, 5, 6, 255>>}},
    {_, C1} = m5_scene_render:plan(none, v([A]), ?S, #{}),
    {_, C2} = m5_scene_render:plan(v([A]), v([B]), ?S, C1),
    {_, C3} = m5_scene_render:plan(v([B]), v([A]), ?S, C2),
    ?assertEqual(2, map_size(C3)).

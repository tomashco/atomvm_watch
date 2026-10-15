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

%% Items that changed position count as changed: their boxes are redrawn, back to front.
reordered_list_redraws_the_swapped_items_test() ->
    A = {rect, 0, 0, 10, 10, 1},
    B = {rect, 5, 5, 10, 10, 2},
    ?assertEqual([{start_write, []}, {set_clip_rect, [0, 0, 15, 15]}, {fill_rect, [0, 0, 15, 15, 0]},
                  {fill_rect, [5, 5, 10, 10, 2]}, {fill_rect, [0, 0, 10, 10, 1]},
                  {clear_clip_rect, []}, {end_write, []}],
                 next([B, A], [A, B])).

reorder_with_another_change_redraws_both_areas_test() ->
    %% A and B overlap and swap stacking order while X, elsewhere, changes colour: A's and B's area
    %% is redrawn, B (now first) drawn last so it ends on top, not only X's box.
    A = {rect, 0, 0, 10, 10, 1},
    B = {rect, 5, 5, 10, 10, 2},
    Ops = next([A, B, {rect, 200, 0, 10, 10, 3}], [B, A, {rect, 200, 0, 10, 10, 4}]),
    ?assert(lists:member({set_clip_rect, [0, 0, 15, 15]}, Ops)),
    ?assert(lists:member({set_clip_rect, [200, 0, 10, 10]}, Ops)),
    {Before, _} = lists:splitwith(fun(Op) -> Op =/= {clear_clip_rect, []} end,
                                  lists:dropwhile(fun(Op) -> Op =/= {set_clip_rect, [0, 0, 15, 15]} end, Ops)),
    ?assertEqual([{fill_rect, [0, 0, 10, 10, 1]}, {fill_rect, [5, 5, 10, 10, 2]}],
                 [Op || {fill_rect, [_, _, 10, 10, _]} = Op <- Before]).

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

%% Many small items moving at once (a rainbow trail's wave flipping): merging their boxes costs
%% more on the watch than redrawing one area, so past 16 changed boxes the area covering them all is
%% redrawn as one region. It also used to be cubic: over 3 s here, half a second on the watch.
many_changed_boxes_redraw_one_covering_region_test_() ->
    {timeout, 30,
     fun() ->
         Grid = fun(DY) -> [{rect, X * 10, Y * 10 + DY, 4, 4, 16#FF} || X <- lists:seq(0, 29), Y <- lists:seq(0, 29)] end,
         {T, {Ops, _}} = timer:tc(fun() -> m5_scene_render:plan(v(Grid(0)), v(Grid(2)), {1000, 1000, 0}, #{}) end),
         ?assertEqual([{set_clip_rect, [0, 0, 294, 296]}], [Op || {set_clip_rect, _} = Op <- Ops]),
         ?assertEqual(2 + 3 + 900, length(Ops)),
         ?assert(T < 500000)
     end}.

few_changed_boxes_redraw_separate_regions_test() ->
    Old = [{rect, X * 20, 0, 4, 4, 1} || X <- lists:seq(0, 3)],
    New = [{rect, X * 20, 0, 4, 4, 2} || X <- lists:seq(0, 3)],
    ?assertEqual(4, length([Op || {set_clip_rect, _} = Op <- next(Old, New)])).

%% The property behind plan/4: its operations, drawn over a screen showing Old, give the screen New
%% gives when drawn from scratch. Random overlapping rects from a small pool on a 6x6 screen, so
%% duplicates, reorders and partial redraws all occur.
plan_turns_old_screen_into_new_test() ->
    rand:seed(exsss, {1, 2, 3}),
    Pool = [{rect, rand:uniform(5) - 1, rand:uniform(5) - 1, rand:uniform(3), rand:uniform(3), rand:uniform(3)}
            || _ <- lists:seq(1, 6)],
    Rand = fun() -> v([lists:nth(rand:uniform(6), Pool) || _ <- lists:seq(1, rand:uniform(7) - 1)]) end,
    Screen = {6, 6, 0},
    lists:foreach(
      fun(_) ->
          Old = Rand(), New = Rand(),
          {Full, _} = m5_scene_render:plan(none, New, Screen, #{}),
          {First, _} = m5_scene_render:plan(none, Old, Screen, #{}),
          {Step, _} = m5_scene_render:plan(Old, New, Screen, #{}),
          ?assertEqual({Old, New, paint(Full, #{})}, {Old, New, paint(Step, paint(First, #{}))})
      end, lists:seq(1, 3000)).

%% A 6x6 canvas as #{{X, Y} => Color}, drawn with the operations rects produce.
paint(Ops, Canvas) -> element(1, lists:foldl(fun op/2, {Canvas, none}, Ops)).

op({fill_rect, [X, Y, W, H, C]}, {Canvas, Clip}) ->
    {lists:foldl(fun(P, Acc) -> maps:put(P, C, Acc) end, Canvas,
                 [{PX, PY} || PX <- lists:seq(X, X + W - 1), PY <- lists:seq(Y, Y + H - 1),
                              PX >= 0, PX < 6, PY >= 0, PY < 6, in_clip(PX, PY, Clip)]), Clip};
op({set_clip_rect, [X, Y, W, H]}, {Canvas, _}) -> {Canvas, {X, Y, W, H}};
op({clear_clip_rect, []}, {Canvas, _}) -> {Canvas, none};
op({start_write, []}, Acc) -> Acc;
op({end_write, []}, Acc) -> Acc.

in_clip(_X, _Y, none) -> true;
in_clip(X, Y, {CX, CY, CW, CH}) -> X >= CX andalso X < CX + CW andalso Y >= CY andalso Y < CY + CH.

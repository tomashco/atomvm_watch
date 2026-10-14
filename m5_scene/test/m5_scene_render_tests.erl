-module(m5_scene_render_tests).
-include_lib("eunit/include/eunit.hrl").

ok(Item) -> {ok, [I], []} = m5_scene_render:validate([Item]), I.
lines(List) -> {ok, _, L} = m5_scene_render:validate(List), L.
reason(Item) -> [L] = lines([Item]), L.

rect_test() ->
    ?assertEqual({rect, 1, 2, 3, 4, 16#FF0000}, ok({rect, 1, 2, 3, 4, 16#1FF0000})),
    ?assertEqual({rect, -32767, 0, 32767, 10, 0}, ok({rect, -100000, 0, 100000, 10, 0})).

text_test() ->
    ?assertEqual({text, 5, 6, 2, 16#FFFFFF, transparent, <<"hé"/utf8>>, 2},
                 ok({text, 5, 6, default16px, 16#FFFFFF, transparent, "hé"})),
    ?assertEqual({text, 0, 0, 3, 0, 16#00FF00, <<"ab">>, 2},
                 ok({text, 0, 0, m5_font3, 0, 16#00FF00, <<"ab">>})).

unsupported_font_falls_back_and_logs_test() ->
    {ok, [{text, 0, 0, 2, _, _, _, _}], Lines} =
        m5_scene_render:validate([{text, 0, 0, comic, 0, 0, "x"}]),
    ?assertEqual([<<"unsupported font: comic">>], Lines).

shapes_test() ->
    ?assertEqual({rounded_rect, 0, 0, 12, 20, 5, 1}, ok({rounded_rect, 0, 0, 12, 20, 9, 1})),
    ?assertEqual({circle, 10, 10, 3, 2}, ok({circle, 10, 10, 3, 2})),
    ?assertEqual({ellipse, 10, 10, 3, 4, 2}, ok({ellipse, 10, 10, 3, 4, 2})),
    ?assertEqual({line, 0, 0, 9, 9, 1, 3}, ok({line, 0, 0, 9, 9, 1, 3})).

image_test() ->
    Px = binary:copy(<<255, 0, 0, 255>>, 4),
    ?assertEqual({image, 1, 2, 0, 2, 2, Px}, ok({image, 1, 2, 0, {rgba8888, 2, 2, Px}})),
    ?assertEqual({image, 1, 2, transparent, 2, 2, Px},
                 ok({image, 1, 2, transparent, {rgba8888, 2, 2, Px}})).

scaled_image_test() ->
    Px = binary:copy(<<0, 0, 255, 255>>, 6),
    %% 3x2 source from (1, 0) at scale 2: at most (3 - 1) * 2 = 4 wide, (2 - 0) * 2 = 4 high.
    ?assertEqual({scaled, 0, 0, 4, 4, 0, 1, 0, 2, 2, true, false, 3, Px},
                 ok({scaled_cropped_image, 0, 0, 100, 100, 0, 1, 0, 2, 2, [flip_x],
                     {rgba8888, 3, 2, Px}})).

invalid_items_are_dropped_and_logged_test() ->
    List = [{rect, 0, 0, 1}, not_a_tuple, {{x}, 1}, {rect, a, 0, 1, 1, 0}, {arc, 1},
            {rect, 0, 0, 1, 1, 0}],
    {ok, Items, Lines} = m5_scene_render:validate(List),
    ?assertEqual([{rect, 0, 0, 1, 1, 0}], Items),
    ?assertEqual([<<"invalid display list item 1 (rect/4): wrong arity">>,
                  <<"invalid display list item 2: not a command tuple">>,
                  <<"invalid display list item 3 (tuple/2): unknown command">>,
                  <<"2 more invalid display list items">>], Lines).

reasons_test() ->
    ?assertEqual(<<"invalid display list item 1 (rect/6): bad position, size or color">>,
                 reason({rect, 0, 0, 1, 1, red})),
    ?assertEqual(<<"invalid display list item 1 (text/7): bad font">>,
                 reason({text, 0, 0, "f", 0, 0, "x"})),
    ?assertEqual(<<"invalid display list item 1 (text/7): bad text">>,
                 reason({text, 0, 0, default16px, 0, 0, 42})),
    ?assertEqual(<<"invalid display list item 1 (image/5): bad image">>,
                 reason({image, 0, 0, 0, {rgba8888, 2, 2, <<0>>}})),
    ?assertEqual(<<"invalid display list item 1 (scaled_cropped_image/12): source outside the image">>,
                 reason({scaled_cropped_image, 0, 0, 1, 1, 0, 5, 0, 1, 1, [],
                         {rgba8888, 1, 1, <<0, 0, 0, 0>>}})),
    ?assertEqual(<<"invalid display list item 1 (circle/5): bad center, radius or color">>,
                 reason({circle, 0, 0, 0, 1})),
    ?assertEqual(<<"invalid display list item 1 (circle/5): bad center, radius or color">>,
                 reason({circle, 40000, 0, 1, 1})),
    ?assertEqual(<<"invalid display list item 1 (line/7): bad points, thickness or color">>,
                 reason({line, 0, 0, 1, 1, 0, 1})),
    ?assertEqual(<<"invalid display list item 1 (polygon/3): unsupported command">>,
                 reason({polygon, [], 0})),
    ?assertEqual(<<"1 more invalid display list item">>,
                 lists:last(lines([x, x, x, x]))).

improper_list_test() ->
    ?assertEqual({error, invalid_display_list}, m5_scene_render:validate([{rect, 0, 0, 1, 1, 0} | tail])),
    ?assertEqual({error, invalid_display_list}, m5_scene_render:validate(not_a_list)),
    ?assertEqual({ok, [], []}, m5_scene_render:validate([])).

bbox_test() ->
    B = fun(I) -> m5_scene_render:bbox(ok(I)) end,
    ?assertEqual({1, 2, 3, 4}, B({rect, 1, 2, 3, 4, 0})),
    ?assertEqual({10, 20, 36, 16}, B({text, 10, 20, default16px, 0, 0, "abc"})),
    ?assertEqual({0, 0, 6, 8}, B({text, 0, 0, m5_font1, 0, 0, <<"é"/utf8>>})),
    ?assertEqual({5, 6, 2, 2}, B({image, 5, 6, 0, {rgba8888, 2, 2, binary:copy(<<0>>, 16)}})),
    ?assertEqual({7, 7, 7, 7}, B({circle, 10, 10, 3, 0})),
    ?assertEqual({7, 6, 7, 9}, B({ellipse, 10, 10, 3, 4, 0})),
    ?assertEqual({0, 0, 12, 20}, B({rounded_rect, 0, 0, 12, 20, 3, 0})),
    ?assertEqual({2, 9, 9, 1}, B({line, 10, 9, 2, 9, 1, 0})),
    %% Thickness 3 pads by (3 - 1) div 2 + 1 = 2 on every side.
    ?assertEqual({0, 7, 13, 5}, B({line, 2, 9, 10, 9, 3, 0})).

%% Pure functions behind m5_scene_display: display list validation and bounding boxes, and the
%% draw plan (plan/4). No side effects, so everything here is tested on the host BEAM.
-module(m5_scene_render).
-export([validate/1, bbox/1, plan/4]).

-define(MAXC, 32767).
-define(LOG_MAX, 3).

%% Checks every item of a display list and normalizes the valid ones: rect and text values clamped
%% to +-32767, colours masked to 24 bits, text as a UTF-8 binary with its character count, fonts
%% as an M5GFX text size. Returns {ok, Items, LogLines}, or {error, invalid_display_list} when
%% List is not a proper list.
validate(List) ->
    case is_proper(List) of
        true -> validate(List, 1, [], [], []);
        false -> {error, invalid_display_list}
    end.

is_proper([]) -> true;
is_proper([_ | T]) -> is_proper(T);
is_proper(_) -> false.

validate([], _N, Items, Invalid, Warnings) ->
    {ok, lists:reverse(Items), invalid_lines(lists:reverse(Invalid)) ++ lists:reverse(Warnings)};
validate([Item | Rest], N, Items, Invalid, Warnings) ->
    case item(Item) of
        {ok, I} -> validate(Rest, N + 1, [I | Items], Invalid, Warnings);
        {ok, I, W} -> validate(Rest, N + 1, [I | Items], Invalid, [W | Warnings]);
        {error, Reason} -> validate(Rest, N + 1, Items, [{N, label(Item), Reason} | Invalid], Warnings)
    end.

item(T) when is_tuple(T), tuple_size(T) > 0 ->
    case element(1, T) of
        rect -> rect(T);
        text -> text(T);
        image -> image(T);
        scaled_cropped_image -> scaled(T);
        rounded_rect -> rounded_rect(T);
        circle -> circle(T);
        ellipse -> ellipse(T);
        line -> line(T);
        arc -> {error, "unsupported command"};
        polygon -> {error, "unsupported command"};
        _ -> {error, "unknown command"}
    end;
item(_) ->
    {error, "not a command tuple"}.

rect({rect, X, Y, W, H, C}) ->
    case ints([X, Y, W, H, C]) of
        true -> {ok, {rect, clamp(X), clamp(Y), clamp(W), clamp(H), C band 16#FFFFFF}};
        false -> {error, "bad position, size or color"}
    end;
rect(_) ->
    {error, "wrong arity"}.

text({text, X, Y, Font, Fg, Bg, Text}) ->
    case ints([X, Y, Fg]) andalso is_bg(Bg) of
        false ->
            {error, "bad position or color"};
        true when not is_atom(Font) ->
            {error, "bad font"};
        true ->
            case utf8(Text) of
                error ->
                    {error, "bad text"};
                Bin ->
                    I = {text, clamp(X), clamp(Y), font_size(Font), Fg band 16#FFFFFF, bg(Bg), Bin,
                         chars(Bin)},
                    case lists:member(Font, [default16px, m5_font1, m5_font2, m5_font3, m5_font4]) of
                        true -> {ok, I};
                        false -> {ok, I, iolist_to_binary(["unsupported font: ", atom_to_list(Font)])}
                    end
            end
    end;
text(_) ->
    {error, "wrong arity"}.

image({image, X, Y, Bg, Img}) ->
    case in_range([X, Y]) andalso is_bg(Bg) of
        false ->
            {error, "bad position or color"};
        true ->
            case image_tuple(Img) of
                {ok, W, H, Px} -> {ok, {image, X, Y, bg(Bg), W, H, Px}};
                error -> {error, "bad image"}
            end
    end;
image(_) ->
    {error, "wrong arity"}.

scaled({scaled_cropped_image, X, Y, W, H, Bg, SX, SY, XS, YS, Opts, Img}) ->
    case in_range([X, Y, W, H, SX, SY, XS, YS]) andalso is_bg(Bg) andalso W >= 0 andalso H >= 0
         andalso XS >= 1 andalso YS >= 1 of
        false ->
            {error, "bad position, size, color, source or scale"};
        true ->
            case image_tuple(Img) of
                error ->
                    {error, "bad image"};
                {ok, IW, IH, Px} when SX >= 0, SX < IW, SY >= 0, SY < IH ->
                    {ok, {scaled, X, Y, min(W, (IW - SX) * XS), min(H, (IH - SY) * YS), bg(Bg),
                          SX, SY, XS, YS, flag(flip_x, Opts), flag(flip_y, Opts), IW, Px}};
                {ok, _, _, _} ->
                    {error, "source outside the image"}
            end
    end;
scaled(_) ->
    {error, "wrong arity"}.

rounded_rect({rounded_rect, X, Y, W, H, R, C}) ->
    case in_range([X, Y, W, H, R]) andalso is_integer(C) andalso R >= 0 of
        true -> {ok, {rounded_rect, X, Y, W, H, min(R, max(0, (min(W, H) - 1) div 2)), C band 16#FFFFFF}};
        false -> {error, "bad position, size, radius or color"}
    end;
rounded_rect(_) ->
    {error, "wrong arity"}.

circle({circle, CX, CY, R, C}) ->
    case in_range([CX, CY, R]) andalso is_integer(C) andalso R > 0 of
        true -> {ok, {circle, CX, CY, R, C band 16#FFFFFF}};
        false -> {error, "bad center, radius or color"}
    end;
circle(_) ->
    {error, "wrong arity"}.

ellipse({ellipse, CX, CY, RX, RY, C}) ->
    case in_range([CX, CY, RX, RY]) andalso is_integer(C) andalso RX > 0 andalso RY > 0 of
        true -> {ok, {ellipse, CX, CY, RX, RY, C band 16#FFFFFF}};
        false -> {error, "bad center, radii or color"}
    end;
ellipse(_) ->
    {error, "wrong arity"}.

line({line, X1, Y1, X2, Y2, T, C}) ->
    case in_range([X1, Y1, X2, Y2, T]) andalso is_integer(C) andalso T >= 1 of
        true -> {ok, {line, X1, Y1, X2, Y2, T, C band 16#FFFFFF}};
        false -> {error, "bad points, thickness or color"}
    end;
line(_) ->
    {error, "wrong arity"}.

image_tuple({rgba8888, W, H, Px}) when is_integer(W), is_integer(H), W >= 1, H >= 1,
                                       W =< ?MAXC, H =< ?MAXC, is_binary(Px),
                                       byte_size(Px) >= W * H * 4 ->
    {ok, W, H, Px};
image_tuple(_) ->
    error.

flag(F, Opts) when is_list(Opts) -> lists:member(F, Opts) orelse lists:member({F, true}, Opts);
flag(_F, _Opts) -> false.

font_size(m5_font1) -> 1;
font_size(m5_font2) -> 2;
font_size(m5_font3) -> 3;
font_size(m5_font4) -> 4;
font_size(_) -> 2.

utf8(B) when is_binary(B) -> B;
utf8(L) when is_list(L) ->
    case catch unicode:characters_to_binary(L) of
        B when is_binary(B) -> B;
        _ -> error
    end;
utf8(_) -> error.

%% Malformed UTF-8 counts one character per byte, as m5_emu does.
chars(Bin) ->
    case catch unicode:characters_to_list(Bin) of
        L when is_list(L) -> length(L);
        _ -> byte_size(Bin)
    end.

is_bg(transparent) -> true;
is_bg(C) -> is_integer(C).

bg(transparent) -> transparent;
bg(C) -> C band 16#FFFFFF.

ints(L) -> lists:all(fun erlang:is_integer/1, L).

in_range(L) -> lists:all(fun(V) -> is_integer(V) andalso V >= -?MAXC andalso V =< ?MAXC end, L).

clamp(V) -> max(-?MAXC, min(?MAXC, V)).

invalid_lines(Invalid) ->
    Shown = lists:sublist(Invalid, ?LOG_MAX),
    [invalid_line(I) || I <- Shown] ++ more_line(length(Invalid) - length(Shown)).

more_line(0) -> [];
more_line(1) -> [<<"1 more invalid display list item">>];
more_line(K) -> [iolist_to_binary([integer_to_list(K), " more invalid display list items"])].

invalid_line({N, none, Reason}) ->
    iolist_to_binary(["invalid display list item ", integer_to_list(N), ": ", Reason]);
invalid_line({N, {Cmd, Arity}, Reason}) ->
    iolist_to_binary(["invalid display list item ", integer_to_list(N), " (", Cmd, "/",
                      integer_to_list(Arity), "): ", Reason]).

label(T) when is_tuple(T), tuple_size(T) > 0 ->
    case element(1, T) of
        A when is_atom(A) -> {atom_to_list(A), tuple_size(T)};
        _ -> {"tuple", tuple_size(T)}
    end;
label(_) ->
    none.

%% Bounding box {X, Y, W, H} of a validated item. Text uses M5GFX's built-in font: 6x8 pixels per
%% character times the text size. A line is padded by half its thickness for the approximation.
bbox({rect, X, Y, W, H, _}) -> {X, Y, W, H};
bbox({text, X, Y, S, _, _, _, N}) -> {X, Y, N * 6 * S, 8 * S};
bbox({image, X, Y, _, W, H, _}) -> {X, Y, W, H};
bbox({scaled, X, Y, W, H, _, _, _, _, _, _, _, _, _}) -> {X, Y, W, H};
bbox({rounded_rect, X, Y, W, H, _, _}) -> {X, Y, W, H};
bbox({circle, CX, CY, R, _}) -> {CX - R, CY - R, 2 * R + 1, 2 * R + 1};
bbox({ellipse, CX, CY, RX, RY, _}) -> {CX - RX, CY - RY, 2 * RX + 1, 2 * RY + 1};
bbox({line, X1, Y1, X2, Y2, T, _}) ->
    P = line_pad(T),
    {min(X1, X2) - P, min(Y1, Y2) - P, abs(X2 - X1) + 1 + 2 * P, abs(Y2 - Y1) + 1 + 2 * P}.

line_pad(1) -> 0;
line_pad(T) -> (T - 1) div 2 + 1.

%% The operations that turn the previous frame Old (validated items, or none before the first
%% frame) into New on a W x H screen with background Bg. Returns {Ops, Cache1}: Ops is a list of
%% {Function, Args} for the display module, Cache1 the image cache restricted to New's images.
plan(Same, Same, _Screen, Cache) ->
    {[], Cache};
plan(Old, New, {W, H, Bg}, Cache) ->
    Screen = {0, 0, W, H},
    {Body, Cache1} =
        case dirty(Old, New, Screen) of
            full -> region(Screen, New, Bg, false, Cache);
            Rects -> regions(Rects, New, Bg, Cache)
        end,
    Ops =
        case Body of
            [] -> [];
            _ -> [{start_write, []}] ++ Body ++ [{end_write, []}]
        end,
    {Ops, m5_scene_image:retain(Cache1, [I || I <- New, m5_scene_image:is_image(I)])}.

%% full, or the merged dirty rectangles: the boxes of the items added and removed, clipped to the
%% screen. Items kept from Old in another order change the stacking everywhere, so that is full too,
%% also when other items changed in the same frame.
dirty(none, _New, _Screen) ->
    full;
dirty(Old, New, {_, _, W, H} = Screen) ->
    Removed = subtract(Old, New),
    Added = subtract(New, Old),
    case subtract(Old, Removed) =:= subtract(New, Added) of
        false ->
            full;
        true ->
            Changed = Removed ++ Added,
            Rects = merge([R || I <- Changed, R <- [clip(bbox(I), Screen)], R =/= empty]),
            case area(Rects) * 2 > W * H of
                true -> full;
                false -> Rects
            end
    end.

regions(Rects, Items, Bg, Cache) ->
    lists:foldl(
        fun(R, {Ops, C}) ->
            {Ops1, C1} = region(R, Items, Bg, true, C),
            {Ops ++ Ops1, C1}
        end, {[], Cache}, Rects).

%% One redraw region: fill it with the background, then draw the items that overlap it from last
%% to first, so the first item ends on top. Clip is true for a dirty rectangle.
region({X, Y, W, H} = R, Items, Bg, Clip, Cache) ->
    {Draw, Cache1} = draw_all([I || I <- lists:reverse(Items), overlaps(bbox(I), R)], Cache),
    Fill = [{fill_rect, [X, Y, W, H, Bg]}],
    case Clip of
        true -> {[{set_clip_rect, [X, Y, W, H]}] ++ Fill ++ Draw ++ [{clear_clip_rect, []}], Cache1};
        false -> {Fill ++ Draw, Cache1}
    end.

draw_all(Items, Cache) ->
    lists:foldl(
        fun(I, {Ops, C}) ->
            {Ops1, C1} = draw(I, C),
            {Ops ++ Ops1, C1}
        end, {[], Cache}, Items).

draw({rect, X, Y, W, H, C}, Cache) ->
    {[{fill_rect, [X, Y, W, H, C]}], Cache};
draw({text, X, Y, S, Fg, Bg, Bin, N}, Cache) ->
    Box = case Bg of
              transparent -> [];
              _ -> [{fill_rect, [X, Y, N * 6 * S, 8 * S, Bg]}]
          end,
    %% The same colour twice is M5GFX's transparent text background.
    {Box ++ [{set_text_size, [S]}, {set_text_color, [Fg, Fg]}, {draw_string, [Bin, X, Y]}], Cache};
draw({rounded_rect, X, Y, W, H, R, C}, Cache) ->
    {[{fill_round_rect, [X, Y, W, H, R, C]}], Cache};
draw({circle, CX, CY, R, C}, Cache) ->
    {[{fill_circle, [CX, CY, R, C]}], Cache};
draw({ellipse, CX, CY, RX, RY, C}, Cache) ->
    {[{fill_ellipse, [CX, CY, RX, RY, C]}], Cache};
draw({line, X1, Y1, X2, Y2, 1, C}, Cache) ->
    {[{draw_line, [X1, Y1, X2, Y2, C]}], Cache};
draw({line, X1, Y1, X2, Y2, T, C}, Cache) ->
    {thick_line(X1, Y1, X2, Y2, T, C), Cache};
draw(Image, Cache) ->
    m5_scene_image:ops(Image, Cache).

%% M5GFX in atomvm_m5 has no wide line: approximate with a quad of two triangles, offset by half
%% the thickness across the line, plus round caps from thickness 3.
thick_line(X, Y, X, Y, T, C) ->
    [{fill_circle, [X, Y, (T - 1) div 2, C]}];
thick_line(X1, Y1, X2, Y2, T, C) ->
    DX = X2 - X1,
    DY = Y2 - Y1,
    Len = math:sqrt(DX * DX + DY * DY),
    Half = (T - 1) / 2,
    OX = round(-DY * Half / Len),
    OY = round(DX * Half / Len),
    Quad = [{fill_triangle, [X1 + OX, Y1 + OY, X2 + OX, Y2 + OY, X2 - OX, Y2 - OY, C]},
            {fill_triangle, [X1 + OX, Y1 + OY, X2 - OX, Y2 - OY, X1 - OX, Y1 - OY, C]}],
    case T >= 3 of
        true -> Quad ++ [{fill_circle, [X1, Y1, (T - 1) div 2, C]}, {fill_circle, [X2, Y2, (T - 1) div 2, C]}];
        false -> Quad
    end.

clip({X, Y, W, H}, {SX, SY, SW, SH}) ->
    X0 = max(X, SX), Y0 = max(Y, SY),
    X1 = min(X + W, SX + SW), Y1 = min(Y + H, SY + SH),
    case X1 > X0 andalso Y1 > Y0 of
        true -> {X0, Y0, X1 - X0, Y1 - Y0};
        false -> empty
    end.

overlaps({X1, Y1, W1, H1}, {X2, Y2, W2, H2}) ->
    W1 > 0 andalso H1 > 0 andalso X1 < X2 + W2 andalso X2 < X1 + W1
        andalso Y1 < Y2 + H2 andalso Y2 < Y1 + H1.

%% Merges overlapping rectangles into their bounding union until none overlap.
merge(Rects) -> merge(Rects, []).

merge([], Acc) ->
    lists:reverse(Acc);
merge([R | Rest], Acc) ->
    case take_overlapping(R, lists:reverse(Acc) ++ Rest, []) of
        none -> merge(Rest, [R | Acc]);
        {Other, Remaining} -> merge([union(R, Other) | Remaining], [])
    end.

take_overlapping(_R, [], _Seen) -> none;
take_overlapping(R, [O | Rest], Seen) ->
    case overlaps(R, O) of
        true -> {O, lists:reverse(Seen) ++ Rest};
        false -> take_overlapping(R, Rest, [O | Seen])
    end.

union({X1, Y1, W1, H1}, {X2, Y2, W2, H2}) ->
    X = min(X1, X2), Y = min(Y1, Y2),
    {X, Y, max(X1 + W1, X2 + W2) - X, max(Y1 + H1, Y2 + H2) - Y}.

area(Rects) -> lists:foldl(fun({_, _, W, H}, A) -> A + W * H end, 0, Rects).

%% L minus one occurrence of each element of R (multiset difference; no -- on AtomVM).
subtract(L, []) -> L;
subtract(L, [X | Xs]) -> subtract(delete(X, L), Xs).

delete(_X, []) -> [];
delete(X, [X | T]) -> T;
delete(X, [H | T]) -> [H | delete(X, T)].

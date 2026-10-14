%% Pure functions behind m5_scene_display: display list validation and bounding boxes, and the
%% draw plan (plan/4). No side effects, so everything here is tested on the host BEAM.
-module(m5_scene_render).
-export([validate/1, bbox/1]).

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

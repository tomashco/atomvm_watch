%% RGBA8888 images to RGB565 push_image operations, with a cache so an image that stays in the
%% display list is converted once. Pure functions.
-module(m5_scene_image).
-export([ops/2, is_image/1, retain/2, rgb565/3, blend/3]).

is_image(Item) -> element(1, Item) =:= image orelse element(1, Item) =:= scaled.

%% The converted runs don't depend on the position, so a moved image keeps its cache entry.
key({image, _X, _Y, Bg, W, H, Px}) ->
    {image, Bg, W, H, Px};
key({scaled, _X, _Y, W, H, Bg, SX, SY, XS, YS, FX, FY, IW, Px}) ->
    {scaled, W, H, Bg, SX, SY, XS, YS, FX, FY, IW, Px}.

%% push_image operations for an image item, and the cache with its entry added.
ops(Item, Cache) ->
    Key = key(Item),
    Runs =
        case maps:find(Key, Cache) of
            {ok, R} -> R;
            error -> convert(Item)
        end,
    X = element(2, Item),
    Y = element(3, Item),
    {[{push_image, [X + DX, Y + DY, W, H, Bin]} || {DX, DY, W, H, Bin} <- Runs],
     maps:put(Key, Runs, Cache)}.

%% The cache restricted to the given image items' entries.
retain(Cache, Images) ->
    lists:foldl(
        fun(I, Acc) ->
            K = key(I),
            case maps:find(K, Cache) of
                {ok, V} -> maps:put(K, V, Acc);
                error -> Acc
            end
        end, #{}, Images).

convert({image, _X, _Y, Bg, W, H, Px}) ->
    runs(W, H, Bg, fun(DX, DY) -> rgba(Px, DY * W + DX) end);
convert({scaled, _X, _Y, W, H, Bg, SX, SY, XS, YS, FX, FY, IW, Px}) ->
    Pixel = fun(DX, DY) ->
                CX = case FX of true -> W - 1 - DX; false -> DX end,
                CY = case FY of true -> H - 1 - DY; false -> DY end,
                rgba(Px, (SY + CY div YS) * IW + SX + CX div XS)
            end,
    runs(W, H, Bg, Pixel).

rgba(Px, I) ->
    <<R, G, B, A>> = binary:part(Px, I * 4, 4),
    {R, G, B, A}.

%% Runs are {DX, DY, W, H, Rgb565}. Opaque background: one run for the whole image, alpha-blended
%% against Bg. transparent: per row, one run for each stretch of pixels with alpha >= 128, unblended.
runs(W, H, _Bg, _Pixel) when W =< 0; H =< 0 ->
    [];
runs(W, H, transparent, Pixel) ->
    lists:append([row_runs(W, DY, Pixel) || DY <- lists:seq(0, H - 1)]);
runs(W, H, Bg, Pixel) ->
    BR = (Bg bsr 16) band 255,
    BG = (Bg bsr 8) band 255,
    BB = Bg band 255,
    Bin = iolist_to_binary(
            [begin
                 {R, G, B, A} = Pixel(DX, DY),
                 rgb565(blend(R, A, BR), blend(G, A, BG), blend(B, A, BB))
             end || DY <- lists:seq(0, H - 1), DX <- lists:seq(0, W - 1)]),
    [{0, 0, W, H, Bin}].

row_runs(W, DY, Pixel) ->
    {Done, Open} =
        lists:foldl(
            fun(DX, {Acc, Cur}) ->
                case Pixel(DX, DY) of
                    {R, G, B, A} when A >= 128 ->
                        case Cur of
                            none -> {Acc, {DX, [rgb565(R, G, B)]}};
                            {Start, Px} -> {Acc, {Start, [rgb565(R, G, B) | Px]}}
                        end;
                    _ ->
                        {close(Cur, DY, Acc), none}
                end
            end, {[], none}, lists:seq(0, W - 1)),
    lists:reverse(close(Open, DY, Done)).

close(none, _DY, Acc) -> Acc;
close({Start, Px}, DY, Acc) -> [{Start, DY, length(Px), 1, iolist_to_binary(lists:reverse(Px))} | Acc].

blend(S, A, B) -> (S * A + B * (255 - A)) div 255.

rgb565(R, G, B) ->
    V = ((R bsr 3) bsl 11) bor ((G bsr 2) bsl 5) bor (B bsr 3),
    <<V:16/big>>.

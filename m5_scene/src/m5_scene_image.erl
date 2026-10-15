%% RGBA8888 images to RGB565 push_image operations, with a cache so an image that stays in the
%% display list is converted once. Pure functions.
-module(m5_scene_image).
-export([ops/2, is_image/1, retain/2, retain/3, rgb565/3, blend/3]).

%% Bytes of RGB565 data kept for images that left the display list, so an animation's frames are
%% converted once and not every time they come back.
-define(KEEP_BYTES, 32768).

is_image(Item) -> element(1, Item) =:= image orelse element(1, Item) =:= scaled.

%% The converted runs don't depend on the position, so a moved image keeps its cache entry.
key({image, _X, _Y, Bg, W, H, Px}) ->
    {image, Bg, W, H, Px};
key({scaled, _X, _Y, W, H, Bg, SX, SY, XS, YS, FX, FY, IW, Px}) ->
    {scaled, W, H, Bg, SX, SY, XS, YS, FX, FY, IW, Px}.

%% push_image operations for an image item, and the cache with its entry added. An entry is
%% {Runs, Bytes, Age}: Age counts the frames since the image was last in the display list.
ops(Item, Cache) ->
    Key = key(Item),
    Entry =
        case maps:find(Key, Cache) of
            {ok, E} -> E;
            error ->
                Runs = convert(Item),
                {Runs, lists:foldl(fun({_, _, _, _, B}, N) -> N + byte_size(B) end, 0, Runs), 0}
        end,
    X = element(2, Item),
    Y = element(3, Item),
    {[{push_image, [X + DX, Y + DY, W, H, Bin]} || {DX, DY, W, H, Bin} <- element(1, Entry)],
     maps:put(Key, Entry, Cache)}.

retain(Cache, Images) ->
    retain(Cache, Images, ?KEEP_BYTES).

%% The cache after a frame showing Images: their entries, plus the entries of images no longer
%% shown, most recently shown first, while their bytes fit in Budget.
retain(Cache, Images, Budget) ->
    Shown = lists:foldl(
              fun(I, Acc) ->
                  K = key(I),
                  case maps:find(K, Cache) of
                      {ok, {Runs, Bytes, _}} -> maps:put(K, {Runs, Bytes, 0}, Acc);
                      error -> Acc
                  end
              end, #{}, Images),
    Dropped = lists:sort([{Age, K, E} || {K, {_, _, Age} = E} <- maps:to_list(Cache),
                                         not maps:is_key(K, Shown)]),
    keep(Dropped, Budget, Shown).

keep([{Age, K, {Runs, Bytes, _}} | Rest], Budget, Acc) when Bytes =< Budget ->
    keep(Rest, Budget - Bytes, maps:put(K, {Runs, Bytes, Age + 1}, Acc));
keep(_, _Budget, Acc) ->
    Acc.

%% Converted one row at a time, walking the RGBA bytes with binary matching: the watch has no PSRAM,
%% and a term per pixel for a whole image would not fit in its heap.
convert({image, _X, _Y, Bg, W, H, Px}) ->
    runs(W, H, Bg, fun(DY) -> binary:part(Px, DY * W * 4, W * 4) end);
convert({scaled, _X, _Y, W, H, Bg, SX, SY, XS, YS, FX, FY, IW, Px}) ->
    Row = fun(DY) ->
              CY = case FY of true -> H - 1 - DY; false -> DY end,
              Src = binary:part(Px, (SY + CY div YS) * IW * 4, IW * 4),
              iolist_to_binary(
                [begin
                     CX = case FX of true -> W - 1 - DX; false -> DX end,
                     binary:part(Src, (SX + CX div XS) * 4, 4)
                 end || DX <- lists:seq(0, W - 1)])
          end,
    runs(W, H, Bg, Row).

%% Runs are {DX, DY, W, H, Rgb565}; Row(DY) is the RGBA bytes of drawn row DY. Opaque background:
%% one run for the whole image, alpha-blended against Bg. transparent: per row, one run for each
%% stretch of pixels with alpha >= 128, unblended.
runs(W, H, _Bg, _Row) when W =< 0; H =< 0 ->
    [];
runs(_W, H, transparent, Row) ->
    lists:append([row_runs(Row(DY), 0, DY, none, []) || DY <- lists:seq(0, H - 1)]);
runs(W, H, Bg, Row) ->
    BG = {(Bg bsr 16) band 255, (Bg bsr 8) band 255, Bg band 255},
    Bin = iolist_to_binary([opaque_row(Row(DY), BG, []) || DY <- lists:seq(0, H - 1)]),
    [{0, 0, W, H, Bin}].

opaque_row(<<R, G, B, A, Rest/binary>>, {BR, BG, BB} = Bg, Acc) ->
    opaque_row(Rest, Bg, [rgb565(blend(R, A, BR), blend(G, A, BG), blend(B, A, BB)) | Acc]);
opaque_row(<<>>, _Bg, Acc) ->
    iolist_to_binary(lists:reverse(Acc)).

row_runs(<<R, G, B, A, Rest/binary>>, DX, DY, Open, Acc) when A >= 128 ->
    Open1 = case Open of
                none -> {DX, [rgb565(R, G, B)]};
                {Start, Px} -> {Start, [rgb565(R, G, B) | Px]}
            end,
    row_runs(Rest, DX + 1, DY, Open1, Acc);
row_runs(<<_:32, Rest/binary>>, DX, DY, Open, Acc) ->
    row_runs(Rest, DX + 1, DY, none, close(Open, DY, Acc));
row_runs(<<>>, _DX, DY, Open, Acc) ->
    lists:reverse(close(Open, DY, Acc)).

close(none, _DY, Acc) -> Acc;
close({Start, Px}, DY, Acc) -> [{Start, DY, length(Px), 1, iolist_to_binary(lists:reverse(Px))} | Acc].

blend(S, A, B) -> (S * A + B * (255 - A)) div 255.

rgb565(R, G, B) ->
    V = ((R bsr 3) bsl 11) bor ((G bsr 2) bsl 5) bor (B bsr 3),
    <<V:16/big>>.

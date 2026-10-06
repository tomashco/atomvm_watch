-module(m5_emu_display).
-behaviour(gen_server).
-export([start_link/1, configure/2, cmd/1, start_write/0, end_write/0, get/1, set/2, reset/0,
         print/1, println/0]).
-export([chars/1]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(CELL_W, 6).
-define(CELL_H, 8).

-record(st, {bridge, native_w = 135, native_h = 240, rotation = 0, cursor = {0, 0},
             text_size = {1, 1}, color = 16#FFFFFF, base_color = 0, sleeping = false,
             brightness = 128, batch = none, depth = 0}).  % batch :: none | [command()] (reversed)

start_link(Bridge) -> gen_server:start_link({local, ?MODULE}, ?MODULE, Bridge, []).
configure(W, H) -> gen_server:call(?MODULE, {configure, W, H}).
cmd(Cmd) -> gen_server:call(?MODULE, {cmd, Cmd}).
start_write() -> gen_server:call(?MODULE, start_write).
end_write() -> gen_server:call(?MODULE, end_write).
get(Key) -> gen_server:call(?MODULE, {get, Key}).
set(Key, Val) -> gen_server:call(?MODULE, {set, Key, Val}).
reset() -> gen_server:call(?MODULE, reset).
print(Bin) -> gen_server:call(?MODULE, {print, Bin}).
println() -> gen_server:call(?MODULE, println).

init(Bridge) -> {ok, #st{bridge = Bridge}}.

handle_call({configure, W, H}, _From, S) -> {reply, ok, S#st{native_w = W, native_h = H}};
handle_call(reset, _From, #st{bridge = B, native_w = W, native_h = H}) -> {reply, ok, #st{bridge = B, native_w = W, native_h = H}};
handle_call({cmd, Cmd}, _From, S) -> {reply, ok, emit(Cmd, S)};
handle_call(start_write, _From, #st{depth = 0} = S) -> {reply, ok, S#st{batch = [], depth = 1}};
handle_call(start_write, _From, #st{depth = D} = S) -> {reply, ok, S#st{depth = D + 1}};
handle_call(end_write, _From, #st{depth = 0} = S) -> {reply, ok, S};
handle_call(end_write, _From, #st{depth = D} = S) when D > 1 -> {reply, ok, S#st{depth = D - 1}};
handle_call(end_write, _From, #st{batch = Cmds} = S) -> {reply, ok, flush(lists:reverse(Cmds), S#st{batch = none, depth = 0})};
handle_call({get, width}, _From, S) -> {reply, width(S), S};
handle_call({get, height}, _From, S) -> {reply, height(S), S};
handle_call({get, rotation}, _From, S) -> {reply, S#st.rotation, S};
handle_call({get, cursor}, _From, S) -> {reply, S#st.cursor, S};
handle_call({get, text_size}, _From, S) -> {reply, S#st.text_size, S};
handle_call({get, color}, _From, S) -> {reply, S#st.color, S};
handle_call({get, base_color}, _From, S) -> {reply, S#st.base_color, S};
handle_call({get, sleeping}, _From, S) -> {reply, S#st.sleeping, S};
handle_call({get, brightness}, _From, S) -> {reply, S#st.brightness, S};
handle_call({set, rotation, R}, _From, S) -> {reply, ok, emit({set_rotation, R}, S#st{rotation = R})};
handle_call({set, cursor, {X, Y}}, _From, S) -> {reply, ok, emit({set_cursor, X, Y}, S#st{cursor = {X, Y}})};
handle_call({set, text_size, {SX, SY}}, _From, S) -> {reply, ok, emit({set_text_size, SX, SY}, S#st{text_size = {SX, SY}})};
handle_call({set, color, C}, _From, S) -> {reply, ok, emit({set_color, C}, S#st{color = C})};
handle_call({set, base_color, C}, _From, S) -> {reply, ok, emit({set_base_color, C}, S#st{base_color = C})};
handle_call({set, sleeping, true}, _From, S) -> {reply, ok, emit({sleep}, S#st{sleeping = true})};
handle_call({set, sleeping, false}, _From, S) -> {reply, ok, emit({wakeup}, S#st{sleeping = false})};
handle_call({set, brightness, Br}, _From, S) -> {reply, ok, emit({set_brightness, Br}, S#st{brightness = Br})};
handle_call({print, Bin}, _From, S) ->
    S1 = emit({print, Bin}, S),
    {reply, byte_size(Bin), S1#st{cursor = advance(Bin, S1)}};
handle_call(println, _From, S) ->
    S1 = emit({println}, S),
    {_, SY} = S#st.text_size, {_, Y} = S#st.cursor,
    {reply, 1, S1#st{cursor = {0, Y + ?CELL_H * SY}}}.

handle_cast(_, S) -> {noreply, S}.

emit(Cmd, #st{batch = none} = S) -> flush([Cmd], S);
emit(Cmd, #st{batch = Cmds} = S) -> S#st{batch = [Cmd | Cmds]}.

flush([], S) -> S;
flush(Cmds, #st{bridge = Bridge} = S) -> ok = Bridge:run_script(m5_emu_cmd:exec_script(Cmds)), S.

width(#st{rotation = R, native_w = W, native_h = H}) -> case R band 1 of 0 -> W; 1 -> H end.
height(#st{rotation = R, native_w = W, native_h = H}) -> case R band 1 of 0 -> H; 1 -> W end.

%% Cursor advance mirrors M5GFX: wrap on X at the right edge, newline resets X. No Y wrap or scroll.
advance(Bin, #st{cursor = {X0, Y0}, text_size = {SX, SY}} = S) ->
    CW = ?CELL_W * SX, CH = ?CELL_H * SY, W = width(S),
    lists:foldl(fun($\n, {_X, Y}) -> {0, Y + CH};
                   ($\r, {_X, Y}) -> {0, Y};
                   (_, {X, Y}) when X + CW > W -> {CW, Y + CH};
                   (_, {X, Y}) -> {X + CW, Y}
                end, {X0, Y0}, chars(Bin)).

%% Code points of Bin; malformed UTF-8 falls back to one cell per byte.
chars(Bin) ->
    case unicode:characters_to_list(Bin) of
        L when is_list(L) -> L;
        _ -> binary_to_list(Bin)
    end.

-module(m5_emu_input).
-behaviour(gen_server).
-export([start_link/0, await_board/1, board/0, update/0, btn/2, btn/3, btn_set/3, battery/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(BUTTONS, [a, b, c, pwr, ext]).
%% levels: current raw level; pending: a down edge not yet seen by update/0 (latch).
-record(st, {board, waiters = [], levels = #{}, pending = #{}, btns = #{}, battery = 100, start}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
await_board(Timeout) -> gen_server:call(?MODULE, {await_board, Timeout}, Timeout + 1000).
board() -> gen_server:call(?MODULE, board).
update() -> gen_server:call(?MODULE, update).
btn(Name, Getter) -> gen_server:call(?MODULE, {btn, Name, Getter, []}).
btn(Name, Getter, Arg) -> gen_server:call(?MODULE, {btn, Name, Getter, [Arg]}).
btn_set(Name, Setter, Ms) -> gen_server:call(?MODULE, {btn_set, Name, Setter, Ms}).
battery() -> gen_server:call(?MODULE, battery).

init([]) ->
    Btns = maps:from_list([{B, m5_emu_btn:new()} || B <- ?BUTTONS]),
    Levels = maps:from_list([{B, false} || B <- ?BUTTONS]),
    {ok, #st{btns = Btns, levels = Levels, pending = Levels,
             start = erlang:monotonic_time(millisecond)}}.

handle_call({await_board, _}, _From, #st{board = {_, _, _} = B} = S) -> {reply, {ok, B}, S};
handle_call({await_board, Timeout}, From, #st{waiters = W} = S) ->
    erlang:send_after(Timeout, self(), {await_timeout, From}),
    {noreply, S#st{waiters = [From | W]}};
handle_call(board, _From, #st{board = undefined} = S) -> {reply, undefined, S};
handle_call(board, _From, #st{board = {Atom, _, _}} = S) -> {reply, Atom, S};
handle_call(update, _From, #st{btns = Btns, levels = Levels, pending = Pending, start = Start} = S) ->
    Now = erlang:monotonic_time(millisecond) - Start,
    New = maps:map(fun(Name, Rec) ->
                       Eff = maps:get(Name, Levels) orelse maps:get(Name, Pending),
                       m5_emu_btn:set_raw_state(Rec, Now, Eff)
                   end, Btns),
    Cleared = maps:map(fun(_, _) -> false end, Pending),
    {reply, ok, S#st{btns = New, pending = Cleared}};
handle_call({btn, Name, Getter, Args}, _From, #st{btns = Btns} = S) ->
    {reply, apply(m5_emu_btn, Getter, [maps:get(Name, Btns) | Args]), S};
handle_call({btn_set, Name, Setter, Ms}, _From, #st{btns = Btns} = S) ->
    {reply, ok, S#st{btns = Btns#{Name := m5_emu_btn:Setter(maps:get(Name, Btns), Ms)}}};
handle_call(battery, _From, S) -> {reply, S#st.battery, S}.

handle_cast(_, S) -> {noreply, S}.

handle_info({emscripten, {cast, Bin}}, S) -> {noreply, handle_message(binary:split(Bin, <<":">>, [global]), S)};
handle_info({await_timeout, From}, #st{waiters = W} = S) ->
    case lists:member(From, W) of
        true -> gen_server:reply(From, {error, timeout}), {noreply, S#st{waiters = lists:delete(From, W)}};
        false -> {noreply, S}
    end;
handle_info(_, S) -> {noreply, S}.

handle_message([<<"board">>, Atom, W, H], #st{waiters = Waiters} = S) ->
    try {binary_to_atom(Atom, utf8), binary_to_integer(W), binary_to_integer(H)} of
        Board ->
            [gen_server:reply(From, {ok, Board}) || From <- Waiters],
            S#st{board = Board, waiters = []}
    catch error:badarg -> S end;
handle_message([Btn, Level], #st{levels = Levels, pending = Pending} = S)
  when Level =:= <<"down">>; Level =:= <<"up">> ->
    case button_name(Btn) of
        undefined -> S;
        Name when Level =:= <<"down">> -> S#st{levels = Levels#{Name := true}, pending = Pending#{Name := true}};
        Name -> S#st{levels = Levels#{Name := false}}
    end;
handle_message([<<"batt">>, N], S) ->
    try S#st{battery = max(0, min(100, binary_to_integer(N)))} catch error:badarg -> S end;
handle_message(_, S) -> S.

%% c and ext never press (spec).
button_name(<<"a">>) -> a;
button_name(<<"b">>) -> b;
button_name(<<"pwr">>) -> pwr;
button_name(_) -> undefined.

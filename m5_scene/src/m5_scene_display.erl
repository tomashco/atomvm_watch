%% avm_scene's display server for m5_display: avm_scene calls call(Pid, {update, DisplayList}) for
%% every pushed frame. Keeps the last valid frame and draws only what changed.
-module(m5_scene_display).
-behaviour(gen_server).
-export([start_link/1, call/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% Opts: #{display := module(), width := integer(), height := integer(), background := integer()}.
start_link(Opts) ->
    case erlang:system_info(machine) of
        "ATOM" ->
            %% AtomVM's gen_server ignores start options, so spawn it through proc_lib. Its default
            %% heap growth keeps only 16-32 free words, so a frame's work triggers a collection every
            %% few allocations, each copying the whole heap; fibonacci grows the heap like OTP.
            proc_lib:start_link(gen_server, init_it, [self(), ?MODULE, Opts, []], infinity,
                                [{atomvm_heap_growth, fibonacci}]);
        _ ->
            gen_server:start_link(?MODULE, Opts, [])
    end.

call(Pid, Msg) ->
    gen_server:call(Pid, Msg, infinity).

init(#{display := D, width := W, height := H, background := Bg}) ->
    {ok, #{display => D, screen => {W, H, Bg band 16#FFFFFF}, last => none, cache => #{}}}.

handle_call({update, List}, _From, #{display := D, screen := Screen, last := Last, cache := Cache} = S) ->
    case m5_scene_render:validate(List) of
        {error, invalid_display_list} ->
            log(<<"invalid display list: not a proper list">>),
            {reply, {error, invalid_display_list}, S};
        {ok, Items, Lines} ->
            lists:foreach(fun log/1, Lines),
            {Ops, Cache1} = m5_scene_render:plan(Last, Items, Screen, Cache),
            lists:foreach(fun({F, A}) -> apply(D, F, A) end, Ops),
            {reply, ok, S#{last := Items, cache := Cache1}}
    end;
handle_call(_Msg, _From, S) ->
    {reply, {error, unknown_call}, S}.

handle_cast(_Msg, S) -> {noreply, S}.
handle_info(_Msg, S) -> {noreply, S}.

log(Line) -> io:format("~s~n", [Line]).

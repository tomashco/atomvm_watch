%% Shared body of every atomvm_m5 function the emulator cannot provide.
%% Returns {error, unsupported} and prints one line per function, the first time it is called, to
%% stdout so the page's console pane shows it. "Already logged" is an ETS table: AtomVM has no
%% persistent_term, and logger is avoided. The table belongs to the process that first logs.
-module(m5_emu_unsupported).
-export([call/3]).

-define(TAB, m5_emu_unsupported_log).

call(Mod, Fun, Arity) ->
    case first_time({Mod, Fun, Arity}) of
        true -> io:format("m5_emu: ~p:~p/~p is not supported in the emulator~n", [Mod, Fun, Arity]);
        false -> ok
    end,
    {error, unsupported}.

first_time(Key) ->
    try
        ensure_table(),
        ets:insert_new(?TAB, {Key})
    catch
        error:_ -> true
    end.

ensure_table() ->
    try ets:new(?TAB, [named_table, public, set]) catch error:badarg -> ok end,
    ok.

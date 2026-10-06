-module(m5).
-export([begin_/1, get_board/0, update/0]).

begin_(Opts) ->
    Bridge = proplists:get_value(bridge, Opts, m5_emu_bridge_emscripten),
    ensure_started(m5_emu_input, fun() -> m5_emu_input:start_link() end),
    ensure_started(m5_emu_display, fun() -> m5_emu_display:start_link(Bridge) end),
    ok = m5_emu_display:reset(),
    ok = Bridge:run_script(<<"m5emu.boardReady()">>),
    case m5_emu_input:await_board(5000) of
        {ok, {_Board, W, H}} -> ok = m5_emu_display:configure(W, H);
        {error, timeout} -> erlang:error({m5_emu, board_handshake_timeout})
    end,
    case proplists:get_value(clear_display, Opts, true) of
        true -> m5_display:clear();
        false -> ok
    end.

get_board() -> m5_emu_input:board().

update() -> m5_emu_input:update().

%% unlink: the servers must outlive the app's start process.
ensure_started(Name, Start) ->
    case whereis(Name) of
        undefined -> {ok, Pid} = Start(), unlink(Pid), ok;
        _Pid -> ok
    end.

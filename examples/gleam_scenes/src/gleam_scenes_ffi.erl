%% The Erlang shapes avm_scene and m5_scene expect that Gleam can't build directly: one tag with two
%% arities ({noreply, S} and {noreply, S, Actions}), a value that is either an integer or an atom,
%% and a module name as an atom.
-module(gleam_scenes_ffi).
-export([noreply/1, push/2, transparent/0, identity/1, module/1, wait_forever/0]).

noreply(State) -> {noreply, State}.

push(State, Items) -> {noreply, State, [{push, Items}]}.

transparent() -> transparent.

identity(X) -> X.

%% The callback module for avm_scene:start_link/3. The module is loaded, so the atom exists.
module(Name) -> binary_to_atom(Name, utf8).

wait_forever() ->
    receive
        stop -> nil
    end.

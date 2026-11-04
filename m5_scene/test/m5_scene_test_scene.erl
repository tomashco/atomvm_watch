%% An avm_scene callback module for m5_scene_tests: a red square at start, green after any input
%% event, which it also forwards to the test process (its init argument).
-module(m5_scene_test_scene).
-export([init/1, handle_info/2, handle_call/3, handle_cast/2, handle_input/4]).

init(TestPid) ->
    self() ! draw,
    {ok, TestPid}.

handle_info(draw, T) -> {noreply, T, [{push, [{rect, 0, 0, 10, 10, 16#FF0000}]}]}.

handle_input(Event, _Ts, _Pid, T) ->
    T ! {scene_input, Event},
    {noreply, T, [{push, [{rect, 0, 0, 10, 10, 16#00FF00}]}]}.

handle_call(_Msg, _From, T) -> {reply, ok, T}.
handle_cast(_Msg, T) -> {noreply, T}.

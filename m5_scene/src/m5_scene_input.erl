%% avm_scene's input server for the M5 buttons. Every poll_ms it calls the button module's update/0
%% (m5:update/0 by default, so this process owns it) and sends each button state change to the
%% subscribers as {input_event, self(), Ts, {button, Name, Event}}.
-module(m5_scene_input).
-behaviour(gen_server).
-export([start_link/1, poll/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(BUTTONS, [a, b, pwr]).
%% Checked in this order on each poll. M5Unified reports was_clicked on the release of a short
%% press and was_double_clicked later, once the click count is decided; a held press reports
%% was_hold and no click.
-define(STATES, [{was_pressed, pressed}, {was_hold, hold}, {was_released, released},
                 {was_clicked, click}, {was_double_clicked, double_click}]).

%% Opts: #{buttons := module(), poll_ms := pos_integer() | infinity}.
start_link(Opts) ->
    gen_server:start_link(?MODULE, Opts, []).

%% One synchronous poll (tests use poll_ms => infinity and call this).
poll(Pid) ->
    gen_server:call(Pid, poll).

%% A button's flags are read for ?ACTIVE_MS after its last change (M5Unified's last_change): long
%% enough for its hold (500 ms by default) and click decisions. Reading every flag of every button on
%% each poll cost a few milliseconds every 10 ms on the watch.
-define(ACTIVE_MS, 2000).

init(#{buttons := B, poll_ms := Ms} = Opts) ->
    schedule(Ms),
    {ok, #{buttons => B, poll_ms => Ms, subs => [], active_ms => maps:get(active_ms, Opts, ?ACTIVE_MS),
           changes => #{}}}.

handle_call({subscribe_input}, {Pid, _Tag}, #{subs := Subs} = S) ->
    case lists:keymember(Pid, 1, Subs) of
        true ->
            {reply, ok, S};
        false ->
            Ref = erlang:monitor(process, Pid),
            {reply, ok, S#{subs := [{Pid, Ref} | Subs]}}
    end;
handle_call(poll, _From, S) ->
    {reply, ok, do_poll(S)};
handle_call(_Msg, _From, S) ->
    {reply, {error, unknown_call}, S}.

handle_info(poll, #{poll_ms := Ms} = S) ->
    S1 = do_poll(S),
    schedule(Ms),
    {noreply, S1};
handle_info({'DOWN', Ref, process, _Pid, _Reason}, #{subs := Subs} = S) ->
    {noreply, S#{subs := lists:keydelete(Ref, 2, Subs)}};
handle_info(_Msg, S) ->
    {noreply, S}.

handle_cast(_Msg, S) -> {noreply, S}.

%% changes: #{Name => {LastChange, SeenAt}}, the button's last_change value and the monotonic time
%% this server first saw it.
do_poll(#{buttons := B, subs := Subs, active_ms := Active, changes := Changes} = S) ->
    B:update(),
    Now = erlang:monotonic_time(millisecond),
    Changes1 = lists:foldl(fun(Name, Acc) -> seen(Name, B:last_change(Name), Now, Acc) end, Changes, ?BUTTONS),
    Events = [{button, Name, Ev} || Name <- ?BUTTONS, active(Name, Changes1, Now, Active),
                                    {Query, Ev} <- ?STATES, B:read(Name, Query)],
    Ts = erlang:system_time(millisecond),
    lists:foreach(fun(E) -> [Pid ! {input_event, self(), Ts, E} || {Pid, _} <- Subs] end, Events),
    S#{changes := Changes1}.

seen(Name, LastChange, Now, Changes) ->
    case maps:find(Name, Changes) of
        {ok, {LastChange, _}} -> Changes;
        _ -> maps:put(Name, {LastChange, Now}, Changes)
    end.

%% The first value seen counts as a change, so every button is read for Active after start.
active(Name, Changes, Now, Active) ->
    {_, SeenAt} = maps:get(Name, Changes),
    Now - SeenAt < Active.

schedule(infinity) -> ok;
schedule(Ms) -> erlang:send_after(Ms, self(), poll), ok.

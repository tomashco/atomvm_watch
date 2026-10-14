%% Entry point: starts the display and input servers that avm_scene needs, drawing through
%% atomvm_m5. Call after m5:begin_/1. An app draws either through m5_scene or directly with
%% m5_display, not both: m5_scene assumes it owns the screen and m5:update/0.
-module(m5_scene).
-export([start_link/1]).

%% Opts (a proplist, or an Elixir keyword list):
%%   rotation   - m5_display rotation, default 1 (landscape, 240x135 on the StickC Plus 2)
%%   poll_ms    - button poll period, default 10
%%   background - colour behind every item, default 16#000000
%% Returns {ok, SceneOpts}, the display_server and input_server options for avm_scene:start_link/3.
%% Both servers are linked to the caller.
start_link(Opts) ->
    Display = proplists:get_value(display_module, Opts, m5_scene_m5),
    Buttons = proplists:get_value(buttons_module, Opts, m5_scene_buttons),
    ok = Display:set_rotation(proplists:get_value(rotation, Opts, 1)),
    {ok, D} = m5_scene_display:start_link(#{display => Display,
                                             width => Display:width(),
                                             height => Display:height(),
                                             background => proplists:get_value(background, Opts, 16#000000)}),
    {ok, I} = m5_scene_input:start_link(#{buttons => Buttons,
                                           poll_ms => proplists:get_value(poll_ms, Opts, 10)}),
    {ok, [{display_server, {m5_scene_display, D}}, {input_server, I}]}.

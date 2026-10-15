%% Button module for tests. States live in a public ETS table owned by the test process: set/1
%% lists the {Name, Query} pairs that read/2 answers true for and counts as a change of each button
%% it names (last_change/1); set_flags/1 does the same without a change, as M5Unified's hold and
%% click flags that come later. updates/0 and reads/0 count update/0 and read/2 calls.
-module(m5_scene_fake_buttons).
-export([new/0, set/1, set_flags/1, updates/0, reads/0, update/0, read/2, last_change/1]).
-define(T, m5_scene_fake_buttons).

new() ->
    catch ets:delete(?T),
    ?T = ets:new(?T, [named_table, public, set]),
    true = ets:insert(?T, [{updates, 0}, {reads, 0}, {{change, a}, 0}, {{change, b}, 0}, {{change, pwr}, 0}]),
    ok.

set(States) ->
    set_flags(States),
    [ets:update_counter(?T, {change, Name}, 1) || Name <- lists:usort([N || {N, _} <- States])],
    ok.

set_flags(States) ->
    ets:match_delete(?T, {{'_', '_'}}),
    [true = ets:insert(?T, {S}) || S <- States],
    ok.

updates() -> ets:lookup_element(?T, updates, 2).
reads() -> ets:lookup_element(?T, reads, 2).
update() -> ets:update_counter(?T, updates, 1), ok.
read(Name, Query) -> ets:update_counter(?T, reads, 1), ets:member(?T, {Name, Query}).
last_change(Name) -> ets:lookup_element(?T, {change, Name}, 2).

%% Button module for tests. States live in a public ETS table owned by the test process: set/1
%% lists the {Name, Query} pairs that read/2 answers true for, updates/0 counts update/0 calls.
-module(m5_scene_fake_buttons).
-export([new/0, set/1, updates/0, update/0, read/2]).
-define(T, m5_scene_fake_buttons).

new() ->
    catch ets:delete(?T),
    ?T = ets:new(?T, [named_table, public, set]),
    true = ets:insert(?T, {updates, 0}),
    ok.

set(States) ->
    ets:match_delete(?T, {{'_', '_'}}),
    [true = ets:insert(?T, {S}) || S <- States],
    ok.

updates() -> ets:lookup_element(?T, updates, 2).
update() -> ets:update_counter(?T, updates, 1), ok.
read(Name, Query) -> ets:member(?T, {Name, Query}).

%% Positive control: a module only the stub pack has, so the smoke app can show the pack was
%% loaded and searched (a shadowing pass is meaningless if the pack never loaded).
-module(stub_pack_probe).
-export([loaded/0]).
loaded() -> true.

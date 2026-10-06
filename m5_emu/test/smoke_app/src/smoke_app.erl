%% Runs under the real AtomVM (node wasm build, see ../node/smoke.mjs) with the load order
%% m5_emu.avm, atomvmlib.avm, smoke_app.avm. Every observation is printed as "SMOKE <key> <value>";
%% the harness asserts on those lines and on the commands it receives through m5emu.exec.
-module(smoke_app).
-behaviour(gen_server).
-export([start/0]).
-export([init/1, handle_call/3, handle_cast/2]).

start() ->
    %% atomvmlib must be loaded: everything in m5_emu is built on gen_server.
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    io:format("SMOKE gen_server ~p~n", [gen_server:call(Pid, ping)]),
    gen_server:stop(Pid),

    ok = m5:begin_([]),
    io:format("SMOKE board ~p ~px~p~n", [m5:get_board(), m5_display:width(), m5_display:height()]),
    m5_display:fill_rect(10, 20, 30, 40, 16#FF0000),
    m5_display:set_cursor(0, 0),
    m5_display:println(<<"hello">>),

    %% Shadowing: test/stub_pack has stub m5 and gpio and loads after m5_emu.avm. The probe module
    %% exists only there, so it proves that pack was loaded; m5 and gpio must still be ours.
    io:format("SMOKE stub_pack_loaded ~p~n", [stub_pack_probe:loaded()]),
    %% gpio shadowing: our gpio forwards the LED to the page as {led, on}.
    io:format("SMOKE gpio ~p~n", [gpio:digital_write(19, high)]),

    %% Unsupported functions return {error, unsupported} and log once per function.
    R1 = m5_imu:get_accel(),
    R2 = m5_imu:get_accel(),
    io:format("SMOKE unsupported ~p ~p~n", [R1, R2]),

    %% JSON encoding of a control character (\u0001), both as text and through the bridge.
    Ctl = <<"a", 1, "b">>,
    io:format("SMOKE json ~s~n", [iolist_to_binary(m5_emu_cmd:encode([{print, Ctl}]))]),
    m5_display:print(Ctl),

    %% Ask the harness to press A, then observe it through the normal polling API.
    %% catch: emscripten:run_script/2 is undef on a real ESP32, so the app still runs on the device.
    catch emscripten:run_script(<<"m5emu.pressA()">>, [main_thread, async]),
    io:format("SMOKE a_was_pressed ~p~n", [poll_pressed(100)]),
    io:format("SMOKE a_pressed ~p~n", [m5_btn_a:is_pressed()]),

    %% Throughput: 1000 fill_rect calls outside a batch (worst case, one run_script each).
    T0 = erlang:monotonic_time(millisecond),
    lists:foreach(fun(I) -> m5_display:fill_rect(I rem 100, 0, 1, 1, I) end, lists:seq(1, 1000)),
    T1 = erlang:monotonic_time(millisecond),
    io:format("SMOKE fill_rect_1000_ms ~p~n", [T1 - T0]),
    %% Same, batched.
    T2 = erlang:monotonic_time(millisecond),
    m5_display:start_write(),
    lists:foreach(fun(I) -> m5_display:fill_rect(I rem 100, 0, 1, 1, I) end, lists:seq(1, 1000)),
    m5_display:end_write(),
    T3 = erlang:monotonic_time(millisecond),
    io:format("SMOKE batched_1000_ms ~p~n", [T3 - T2]),
    io:format("SMOKE done~n"),
    ok.

%% The cast arrives asynchronously (run_script -> JS -> Module.cast), so poll update/0 for up to
%% N * 10 ms. was_pressed/0 is true only on the update that sees the down edge.
poll_pressed(0) ->
    false;
poll_pressed(N) ->
    ok = m5:update(),
    case m5_btn_a:was_pressed() of
        true -> true;
        false -> timer:sleep(10), poll_pressed(N - 1)
    end.

init([]) -> {ok, nil}.
handle_call(ping, _From, S) -> {reply, pong, S}.
handle_cast(_, S) -> {noreply, S}.

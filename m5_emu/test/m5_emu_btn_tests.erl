-module(m5_emu_btn_tests).
-include_lib("eunit/include/eunit.hrl").

%% Feed a list of {Msec, Pressed} samples, return the final record.
feed(Samples) -> lists:foldl(fun({T, P}, B) -> m5_emu_btn:set_raw_state(B, T, P) end, m5_emu_btn:new(), Samples).

fresh_state_test() ->
    B = m5_emu_btn:new(),
    ?assertNot(m5_emu_btn:is_pressed(B)),
    ?assert(m5_emu_btn:is_released(B)),
    ?assertNot(m5_emu_btn:was_pressed(B)),
    ?assertNot(m5_emu_btn:was_released(B)),
    ?assertEqual(0, m5_emu_btn:get_click_count(B)).

press_is_debounced_test() ->
    %% Raw level goes high at t=0 and is sampled again at t=5 (< 10 ms debounce): still released.
    B5 = feed([{0, true}, {5, true}]),
    ?assertNot(m5_emu_btn:is_pressed(B5)),
    %% At t=10 the level has been stable for 10 ms: pressed, and was_pressed for this cycle.
    B10 = m5_emu_btn:set_raw_state(B5, 10, true),
    ?assert(m5_emu_btn:is_pressed(B10)),
    ?assert(m5_emu_btn:was_pressed(B10)),
    %% One more cycle: still pressed, but the edge flag is gone.
    B20 = m5_emu_btn:set_raw_state(B10, 20, true),
    ?assert(m5_emu_btn:is_pressed(B20)),
    ?assertNot(m5_emu_btn:was_pressed(B20)).

click_test() ->
    B = feed([{0, true}, {10, true}, {100, false}]),
    ?assert(m5_emu_btn:was_released(B)),
    ?assert(m5_emu_btn:was_clicked(B)),
    ?assertEqual(1, m5_emu_btn:get_click_count(B)),
    B1 = m5_emu_btn:set_raw_state(B, 110, false),
    %% After the hold timeout (500 ms) with no second click, the count is decided.
    B2 = m5_emu_btn:set_raw_state(B1, 700, false),
    ?assert(m5_emu_btn:was_decide_click_count(B2)),
    ?assert(m5_emu_btn:was_single_clicked(B2)),
    B3 = m5_emu_btn:set_raw_state(B2, 710, false),
    ?assertNot(m5_emu_btn:was_single_clicked(B3)),
    ?assertEqual(0, m5_emu_btn:get_click_count(B3)).

double_click_test() ->
    B = feed([{0, true}, {10, true}, {100, false}, {110, false},
              {200, true}, {210, true}, {300, false}, {310, false}, {900, false}]),
    ?assert(m5_emu_btn:was_double_clicked(B)).

hold_test() ->
    B = feed([{0, true}, {10, true}, {300, true}]),
    ?assertNot(m5_emu_btn:is_holding(B)),
    B2 = m5_emu_btn:set_raw_state(B, 520, true),
    ?assert(m5_emu_btn:is_holding(B2)),
    ?assert(m5_emu_btn:was_hold(B2)),
    ?assert(m5_emu_btn:pressed_for(B2, 500)),
    B3 = feed([{0, true}, {10, true}, {520, true}, {600, false}]),
    ?assert(m5_emu_btn:was_released_after_hold(B3)),
    ?assert(m5_emu_btn:was_released_for(B3, 500)),
    ?assertNot(m5_emu_btn:was_clicked(B3)).

thresholds_test() ->
    B = m5_emu_btn:set_hold_thresh(m5_emu_btn:set_debounce_thresh(m5_emu_btn:new(), 0), 100),
    ?assertEqual(0, m5_emu_btn:get_debounce_thresh(B)),
    ?assertEqual(100, m5_emu_btn:get_hold_thresh(B)),
    B2 = feed_from(B, [{0, true}, {1, true}, {150, true}]),
    ?assert(m5_emu_btn:is_holding(B2)).

feed_from(B0, Samples) -> lists:foldl(fun({T, P}, B) -> m5_emu_btn:set_raw_state(B, T, P) end, B0, Samples).

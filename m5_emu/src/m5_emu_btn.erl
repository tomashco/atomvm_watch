-module(m5_emu_btn).
-include("m5_emu_btn.hrl").
-export([new/0, set_raw_state/3,
         was_clicked/1, was_hold/1, was_single_clicked/1, was_double_clicked/1,
         was_decide_click_count/1, get_click_count/1, is_holding/1, was_change_pressed/1,
         is_pressed/1, is_released/1, was_pressed/1, was_released/1, was_released_after_hold/1,
         was_released_for/2, pressed_for/2, release_for/2,
         set_debounce_thresh/2, set_hold_thresh/2, last_change/1,
         get_debounce_thresh/1, get_hold_thresh/1, get_update_msec/1]).
-export_type([btn/0]).
-type btn() :: #btn{}.

new() -> #btn{}.

%% Port of Button_Class::setRawState (M5Unified 0.2.10).
set_raw_state(#btn{} = B0, Msec, Press) ->
    DisableDb = (Msec - B0#btn.last_msec) > B0#btn.msec_debounce,
    OldPress = B0#btn.press,
    B1 = B0#btn{old_press = OldPress},
    B2 = case B1#btn.raw_press =/= Press of
             true -> B1#btn{raw_press = Press, last_raw_change = Msec};
             false -> B1
         end,
    {B3, State} =
        case DisableDb orelse (Msec - B2#btn.last_raw_change >= B2#btn.msec_debounce) of
            true ->
                Bc = case Press =/= (OldPress =/= 0) of
                         true -> B2#btn{last_change = Msec};
                         false -> B2
                     end,
                case Press of
                    true ->
                        Hold = Msec - Bc#btn.last_change,
                        Bh = Bc#btn{last_hold_period = Hold},
                        if OldPress =:= 0 -> {Bh#btn{press = 1}, nochange};
                           OldPress =:= 1, Hold >= Bh#btn.msec_hold -> {Bh#btn{press = 2}, hold};
                           true -> {Bh, nochange}
                        end;
                    false ->
                        Br = Bc#btn{press = 0},
                        case OldPress of 1 -> {Br, clicked}; _ -> {Br, nochange} end
                end;
            false -> {B2, nochange}
        end,
    set_state(B3, Msec, State).

%% Port of Button_Class::setState.
set_state(#btn{} = B0, Msec, State0) ->
    B1 = case B0#btn.state of decide_click_count -> B0#btn{click_count = 0}; _ -> B0 end,
    B2 = B1#btn{last_msec = Msec},
    Timeout = (Msec - B2#btn.last_clicked) > B2#btn.msec_hold,
    {B3, State} =
        case State0 of
            nochange when Timeout, B2#btn.press =:= 0, B2#btn.click_count =/= 0 ->
                case B2#btn.old_press =:= 0 andalso B2#btn.state =:= nochange of
                    true -> {B2, decide_click_count};
                    false -> {B2#btn{click_count = 0}, nochange}
                end;
            clicked -> {B2#btn{click_count = B2#btn.click_count + 1, last_clicked = Msec}, clicked};
            Other -> {B2, Other}
        end,
    B3#btn{state = State}.

was_clicked(#btn{state = S}) -> S =:= clicked.
was_hold(#btn{state = S}) -> S =:= hold.
was_single_clicked(#btn{state = S, click_count = C}) -> S =:= decide_click_count andalso C =:= 1.
was_double_clicked(#btn{state = S, click_count = C}) -> S =:= decide_click_count andalso C =:= 2.
was_decide_click_count(#btn{state = S}) -> S =:= decide_click_count.
get_click_count(#btn{click_count = C}) -> C.
is_holding(#btn{press = P}) -> P =:= 2.
was_change_pressed(#btn{press = P, old_press = O}) -> (P =/= 0) =/= (O =/= 0).
is_pressed(#btn{press = P}) -> P =/= 0.
is_released(#btn{press = P}) -> P =:= 0.
was_pressed(#btn{press = P, old_press = O}) -> O =:= 0 andalso P =/= 0.
was_released(#btn{press = P, old_press = O}) -> O =/= 0 andalso P =:= 0.
was_released_after_hold(#btn{press = P, old_press = O}) -> P =:= 0 andalso O =:= 2.
was_released_for(#btn{press = P, old_press = O, last_hold_period = H}, Ms) -> O =/= 0 andalso P =:= 0 andalso H >= Ms.
pressed_for(#btn{press = P, last_msec = T, last_change = C}, Ms) -> P =/= 0 andalso T - C >= Ms.
release_for(#btn{press = P, last_msec = T, last_change = C}, Ms) -> P =:= 0 andalso T - C >= Ms.
set_debounce_thresh(B, Ms) -> B#btn{msec_debounce = Ms}.
set_hold_thresh(B, Ms) -> B#btn{msec_hold = Ms}.
last_change(#btn{last_change = C}) -> C.
get_debounce_thresh(#btn{msec_debounce = D}) -> D.
get_hold_thresh(#btn{msec_hold = H}) -> H.
get_update_msec(#btn{last_msec = T}) -> T.

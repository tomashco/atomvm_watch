%% The 22 functions of atomvm_m5's button NIF table. Define ?BTN before including.
-export([was_clicked/0, was_hold/0, was_single_clicked/0, was_double_clicked/0, was_decide_click_count/0,
         get_click_count/0, is_holding/0, was_change_pressed/0, is_pressed/0, is_released/0, was_pressed/0,
         was_released/0, was_released_after_hold/0, was_released_for/1, pressed_for/1, release_for/1,
         set_debounce_thresh/1, set_hold_thresh/1, last_change/0, get_debounce_thresh/0, get_hold_thresh/0,
         get_update_msec/0]).
was_clicked() -> m5_emu_input:btn(?BTN, was_clicked).
was_hold() -> m5_emu_input:btn(?BTN, was_hold).
was_single_clicked() -> m5_emu_input:btn(?BTN, was_single_clicked).
was_double_clicked() -> m5_emu_input:btn(?BTN, was_double_clicked).
was_decide_click_count() -> m5_emu_input:btn(?BTN, was_decide_click_count).
get_click_count() -> m5_emu_input:btn(?BTN, get_click_count).
is_holding() -> m5_emu_input:btn(?BTN, is_holding).
was_change_pressed() -> m5_emu_input:btn(?BTN, was_change_pressed).
is_pressed() -> m5_emu_input:btn(?BTN, is_pressed).
is_released() -> m5_emu_input:btn(?BTN, is_released).
was_pressed() -> m5_emu_input:btn(?BTN, was_pressed).
was_released() -> m5_emu_input:btn(?BTN, was_released).
was_released_after_hold() -> m5_emu_input:btn(?BTN, was_released_after_hold).
was_released_for(Ms) -> m5_emu_input:btn(?BTN, was_released_for, Ms).
pressed_for(Ms) -> m5_emu_input:btn(?BTN, pressed_for, Ms).
release_for(Ms) -> m5_emu_input:btn(?BTN, release_for, Ms).
set_debounce_thresh(Ms) -> m5_emu_input:btn_set(?BTN, set_debounce_thresh, Ms).
set_hold_thresh(Ms) -> m5_emu_input:btn_set(?BTN, set_hold_thresh, Ms).
last_change() -> m5_emu_input:btn(?BTN, last_change).
get_debounce_thresh() -> m5_emu_input:btn(?BTN, get_debounce_thresh).
get_hold_thresh() -> m5_emu_input:btn(?BTN, get_hold_thresh).
get_update_msec() -> m5_emu_input:btn(?BTN, get_update_msec).

%% The default button module: static calls into atomvm_m5 (see m5_scene_m5 for why static).
-module(m5_scene_buttons).
-export([update/0, read/2]).

update() -> m5:update().

read(a, Q) -> a(Q);
read(b, Q) -> b(Q);
read(pwr, Q) -> pwr(Q).

a(was_pressed) -> m5_btn_a:was_pressed();
a(was_hold) -> m5_btn_a:was_hold();
a(was_released) -> m5_btn_a:was_released();
a(was_clicked) -> m5_btn_a:was_clicked();
a(was_double_clicked) -> m5_btn_a:was_double_clicked().

b(was_pressed) -> m5_btn_b:was_pressed();
b(was_hold) -> m5_btn_b:was_hold();
b(was_released) -> m5_btn_b:was_released();
b(was_clicked) -> m5_btn_b:was_clicked();
b(was_double_clicked) -> m5_btn_b:was_double_clicked().

pwr(was_pressed) -> m5_btn_pwr:was_pressed();
pwr(was_hold) -> m5_btn_pwr:was_hold();
pwr(was_released) -> m5_btn_pwr:was_released();
pwr(was_clicked) -> m5_btn_pwr:was_clicked();
pwr(was_double_clicked) -> m5_btn_pwr:was_double_clicked().

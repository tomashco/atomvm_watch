-module(m5_display).
-export([set_epd_mode/1, set_brightness/1, sleep/0, wakeup/0, power_save/1, power_save_on/0, power_save_off/0,
         set_color/1, set_color/3, set_raw_color/1, get_raw_color/0, set_base_color/1, get_base_color/0,
         start_write/0, end_write/0,
         write_pixel/2, write_pixel/3, write_fast_vline/3, write_fast_vline/4, write_fast_hline/3, write_fast_hline/4,
         write_fill_rect/4, write_fill_rect/5, write_fill_rect_preclipped/4, write_fill_rect_preclipped/5,
         write_color/2, push_block/2,
         draw_pixel/2, draw_pixel/3, draw_fast_vline/3, draw_fast_vline/4, draw_fast_hline/3, draw_fast_hline/4,
         fill_rect/4, fill_rect/5, draw_rect/4, draw_rect/5, draw_round_rect/5, draw_round_rect/6,
         fill_round_rect/5, fill_round_rect/6, draw_circle/3, draw_circle/4, fill_circle/3, fill_circle/4,
         draw_ellipse/4, draw_ellipse/5, fill_ellipse/4, fill_ellipse/5, draw_line/4, draw_line/5,
         draw_triangle/6, draw_triangle/7, fill_triangle/6, fill_triangle/7,
         draw_bezier/6, draw_bezier/7, draw_bezier/8, draw_bezier/9,
         fill_screen/0, fill_screen/1, clear/0, clear/1, width/0, height/0, wait_display/0, display_busy/0,
         set_auto_display/1, get_rotation/0, set_rotation/1, set_clip_rect/4, get_clip_rect/0, clear_clip_rect/0,
         set_scroll_rect/4, get_scroll_rect/0, clear_scroll_rect/0, get_cursor/0, set_cursor/2,
         set_text_size/1, set_text_size/2, font_height/0, font_width/0,
         draw_string/3, draw_center_string/3, draw_right_string/3, print/1, println/1, println/0]).

-define(UNSUPPORTED, {error, unsupported}).
color() -> m5_emu_display:get(color).
c(Color) -> m5_emu_cmd:to_rgb888(Color).

set_epd_mode(_) -> ok.
set_brightness(B) -> m5_emu_display:set(brightness, B).
sleep() -> m5_emu_display:set(sleeping, true).
wakeup() -> m5_emu_display:set(sleeping, false).
power_save(_) -> ok.  power_save_on() -> ok.  power_save_off() -> ok.
set_color(Color) -> m5_emu_display:set(color, c(Color)).
set_color(R, G, B) -> set_color({rgb, {R, G, B}}).
set_raw_color(Raw) -> set_color({rgb565, Raw}).
get_raw_color() -> ?UNSUPPORTED.
set_base_color(Color) -> m5_emu_display:set(base_color, c(Color)).
get_base_color() -> m5_emu_display:get(base_color).
start_write() -> m5_emu_display:start_write().
end_write() -> m5_emu_display:end_write().
write_pixel(X, Y) -> draw_pixel(X, Y).           write_pixel(X, Y, C) -> draw_pixel(X, Y, C).
write_fast_vline(X, Y, H) -> draw_fast_vline(X, Y, H).  write_fast_vline(X, Y, H, C) -> draw_fast_vline(X, Y, H, C).
write_fast_hline(X, Y, W) -> draw_fast_hline(X, Y, W).  write_fast_hline(X, Y, W, C) -> draw_fast_hline(X, Y, W, C).
write_fill_rect(X, Y, W, H) -> fill_rect(X, Y, W, H).   write_fill_rect(X, Y, W, H, C) -> fill_rect(X, Y, W, H, C).
write_fill_rect_preclipped(X, Y, W, H) -> fill_rect(X, Y, W, H).
write_fill_rect_preclipped(X, Y, W, H, C) -> fill_rect(X, Y, W, H, C).
write_color(_, _) -> ?UNSUPPORTED.  push_block(_, _) -> ?UNSUPPORTED.
draw_pixel(X, Y) -> draw_pixel(X, Y, color()).
draw_pixel(X, Y, C) -> m5_emu_display:cmd({draw_pixel, X, Y, c(C)}).
draw_fast_vline(X, Y, H) -> draw_fast_vline(X, Y, H, color()).
draw_fast_vline(X, Y, H, C) -> m5_emu_display:cmd({draw_fast_vline, X, Y, H, c(C)}).
draw_fast_hline(X, Y, W) -> draw_fast_hline(X, Y, W, color()).
draw_fast_hline(X, Y, W, C) -> m5_emu_display:cmd({draw_fast_hline, X, Y, W, c(C)}).
fill_rect(X, Y, W, H) -> fill_rect(X, Y, W, H, color()).
fill_rect(X, Y, W, H, C) -> m5_emu_display:cmd({fill_rect, X, Y, W, H, c(C)}).
draw_rect(X, Y, W, H) -> draw_rect(X, Y, W, H, color()).
draw_rect(X, Y, W, H, C) -> m5_emu_display:cmd({draw_rect, X, Y, W, H, c(C)}).
draw_round_rect(X, Y, W, H, R) -> draw_round_rect(X, Y, W, H, R, color()).
draw_round_rect(X, Y, W, H, R, C) -> m5_emu_display:cmd({draw_round_rect, X, Y, W, H, R, c(C)}).
fill_round_rect(X, Y, W, H, R) -> fill_round_rect(X, Y, W, H, R, color()).
fill_round_rect(X, Y, W, H, R, C) -> m5_emu_display:cmd({fill_round_rect, X, Y, W, H, R, c(C)}).
draw_circle(X, Y, R) -> draw_circle(X, Y, R, color()).
draw_circle(X, Y, R, C) -> m5_emu_display:cmd({draw_circle, X, Y, R, c(C)}).
fill_circle(X, Y, R) -> fill_circle(X, Y, R, color()).
fill_circle(X, Y, R, C) -> m5_emu_display:cmd({fill_circle, X, Y, R, c(C)}).
draw_ellipse(X, Y, RX, RY) -> draw_ellipse(X, Y, RX, RY, color()).
draw_ellipse(X, Y, RX, RY, C) -> m5_emu_display:cmd({draw_ellipse, X, Y, RX, RY, c(C)}).
fill_ellipse(X, Y, RX, RY) -> fill_ellipse(X, Y, RX, RY, color()).
fill_ellipse(X, Y, RX, RY, C) -> m5_emu_display:cmd({fill_ellipse, X, Y, RX, RY, c(C)}).
draw_line(X0, Y0, X1, Y1) -> draw_line(X0, Y0, X1, Y1, color()).
draw_line(X0, Y0, X1, Y1, C) -> m5_emu_display:cmd({draw_line, X0, Y0, X1, Y1, c(C)}).
draw_triangle(X0, Y0, X1, Y1, X2, Y2) -> draw_triangle(X0, Y0, X1, Y1, X2, Y2, color()).
draw_triangle(X0, Y0, X1, Y1, X2, Y2, C) -> m5_emu_display:cmd({draw_triangle, X0, Y0, X1, Y1, X2, Y2, c(C)}).
fill_triangle(X0, Y0, X1, Y1, X2, Y2) -> fill_triangle(X0, Y0, X1, Y1, X2, Y2, color()).
fill_triangle(X0, Y0, X1, Y1, X2, Y2, C) -> m5_emu_display:cmd({fill_triangle, X0, Y0, X1, Y1, X2, Y2, c(C)}).
draw_bezier(_, _, _, _, _, _) -> ?UNSUPPORTED.  draw_bezier(_, _, _, _, _, _, _) -> ?UNSUPPORTED.
draw_bezier(_, _, _, _, _, _, _, _) -> ?UNSUPPORTED.  draw_bezier(_, _, _, _, _, _, _, _, _) -> ?UNSUPPORTED.
fill_screen() -> fill_screen(color()).
fill_screen(C) -> m5_emu_display:cmd({fill_screen, c(C)}).
clear() -> clear(get_base_color()).
clear(C) -> m5_emu_display:cmd({fill_screen, c(C)}).
width() -> m5_emu_display:get(width).
height() -> m5_emu_display:get(height).
wait_display() -> ok.  display_busy() -> false.  set_auto_display(_) -> ok.
get_rotation() -> m5_emu_display:get(rotation).
set_rotation(R) when R >= 0, R =< 3 -> m5_emu_display:set(rotation, R).
set_clip_rect(_, _, _, _) -> ?UNSUPPORTED.  get_clip_rect() -> ?UNSUPPORTED.  clear_clip_rect() -> ok.
set_scroll_rect(_, _, _, _) -> ?UNSUPPORTED.  get_scroll_rect() -> ?UNSUPPORTED.  clear_scroll_rect() -> ok.
get_cursor() -> m5_emu_display:get(cursor).
set_cursor(X, Y) -> m5_emu_display:set(cursor, {X, Y}).
set_text_size(S) -> set_text_size(S, S).
set_text_size(SX, SY) -> m5_emu_display:set(text_size, {SX, SY}).
font_height() -> {_, SY} = m5_emu_display:get(text_size), round(8 * SY).
font_width() -> {SX, _} = m5_emu_display:get(text_size), round(6 * SX).
draw_string(S, X, Y) -> m5_emu_display:cmd({draw_string, iolist_to_binary(S), X, Y}), font_width() * length(m5_emu_display:chars(iolist_to_binary(S))).
draw_center_string(S, X, Y) -> m5_emu_display:cmd({draw_center_string, iolist_to_binary(S), X, Y}), font_width() * length(m5_emu_display:chars(iolist_to_binary(S))).
draw_right_string(S, X, Y) -> m5_emu_display:cmd({draw_right_string, iolist_to_binary(S), X, Y}), font_width() * length(m5_emu_display:chars(iolist_to_binary(S))).
print(S) -> m5_emu_display:print(iolist_to_binary(S)).
println(S) -> N = print(S), N + println().
println() -> m5_emu_display:println().

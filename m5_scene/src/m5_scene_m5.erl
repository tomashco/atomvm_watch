%% The default display module: static calls into atomvm_m5's m5_display. m5_scene_display calls
%% its display module through a variable; keeping the m5_display calls static here means the NIFs
%% resolve on the device exactly as they do for an app that calls m5_display directly.
-module(m5_scene_m5).
-export([set_rotation/1, width/0, height/0, start_write/0, end_write/0, fill_rect/5,
         set_clip_rect/4, clear_clip_rect/0, set_text_size/1, set_text_color/2, draw_string/3,
         push_image/5, fill_round_rect/6, fill_circle/4, fill_ellipse/5, draw_line/5,
         fill_triangle/7]).

set_rotation(R) -> m5_display:set_rotation(R).
width() -> m5_display:width().
height() -> m5_display:height().
start_write() -> m5_display:start_write().
end_write() -> m5_display:end_write().
fill_rect(X, Y, W, H, C) -> m5_display:fill_rect(X, Y, W, H, C).
set_clip_rect(X, Y, W, H) -> m5_display:set_clip_rect(X, Y, W, H).
clear_clip_rect() -> m5_display:clear_clip_rect().
set_text_size(S) -> m5_display:set_text_size(S).
set_text_color(F, B) -> m5_display:set_text_color(F, B).
draw_string(S, X, Y) -> m5_display:draw_string(S, X, Y).
push_image(X, Y, W, H, B) -> m5_display:push_image(X, Y, W, H, B).
fill_round_rect(X, Y, W, H, R, C) -> m5_display:fill_round_rect(X, Y, W, H, R, C).
fill_circle(X, Y, R, C) -> m5_display:fill_circle(X, Y, R, C).
fill_ellipse(X, Y, RX, RY, C) -> m5_display:fill_ellipse(X, Y, RX, RY, C).
draw_line(X1, Y1, X2, Y2, C) -> m5_display:draw_line(X1, Y1, X2, Y2, C).
fill_triangle(X1, Y1, X2, Y2, X3, Y3, C) -> m5_display:fill_triangle(X1, Y1, X2, Y2, X3, Y3, C).

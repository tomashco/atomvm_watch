%% Display module for tests: records every call as {display, Fun, Args} to the process registered
%% as m5_scene_test_sink, on a 240x135 screen.
-module(m5_scene_fake_display).
-export([set_rotation/1, width/0, height/0, start_write/0, end_write/0, fill_rect/5,
         set_clip_rect/4, clear_clip_rect/0, set_text_size/1, set_text_color/2, draw_string/3,
         push_image/5, fill_round_rect/6, fill_circle/4, fill_ellipse/5, draw_line/5,
         fill_triangle/7]).
-export([calls/0, frame/0]).

rec(F, A) -> m5_scene_test_sink ! {display, F, A}, ok.

set_rotation(R) -> rec(set_rotation, [R]).
width() -> 240.
height() -> 135.
start_write() -> rec(start_write, []).
end_write() -> rec(end_write, []).
fill_rect(X, Y, W, H, C) -> rec(fill_rect, [X, Y, W, H, C]).
set_clip_rect(X, Y, W, H) -> rec(set_clip_rect, [X, Y, W, H]).
clear_clip_rect() -> rec(clear_clip_rect, []).
set_text_size(S) -> rec(set_text_size, [S]).
set_text_color(F, B) -> rec(set_text_color, [F, B]).
draw_string(S, X, Y) -> rec(draw_string, [S, X, Y]), 0.
push_image(X, Y, W, H, B) -> rec(push_image, [X, Y, W, H, B]).
fill_round_rect(X, Y, W, H, R, C) -> rec(fill_round_rect, [X, Y, W, H, R, C]).
fill_circle(X, Y, R, C) -> rec(fill_circle, [X, Y, R, C]).
fill_ellipse(X, Y, RX, RY, C) -> rec(fill_ellipse, [X, Y, RX, RY, C]).
draw_line(X1, Y1, X2, Y2, C) -> rec(draw_line, [X1, Y1, X2, Y2, C]).
fill_triangle(X1, Y1, X2, Y2, X3, Y3, C) -> rec(fill_triangle, [X1, Y1, X2, Y2, X3, Y3, C]).

%% The calls already in the mailbox, in order.
calls() -> receive {display, F, A} -> [{F, A} | calls()] after 0 -> [] end.

%% The calls of one frame, waiting for it: up to and including end_write.
frame() ->
    receive
        {display, end_write, []} -> [{end_write, []}];
        {display, F, A} -> [{F, A} | frame()]
    after 1000 -> [timeout]
    end.

//// Gleam example: a counter drawn directly with m5_display. A adds one, B beeps and resets.
//// Runs in the emulator and on the watch; build it with scripts/build-gleam-example.sh.

import gleam/int
import gleam_hello/m5

const background = 0x1E1E2E

const pink = 0xFFAFF3

const muted = 0x9AA0A8

/// The entry point AtomVM calls: packbeam makes this module the start module.
pub fn start() -> Nil {
  m5.begin([])
  m5.set_rotation(1)
  draw(0)
  loop(0)
}

fn loop(count: Int) -> Nil {
  m5.sleep(10)
  m5.update()
  let next = step(count, m5.a_was_pressed(), m5.b_was_pressed())
  case next == count {
    True -> Nil
    False -> draw(next)
  }
  loop(next)
}

/// The new count after a poll. B wins when both buttons were pressed.
fn step(count: Int, a: Bool, b: Bool) -> Int {
  case a, b {
    _, True -> {
      m5.tone(1800, 80)
      0
    }
    True, False -> count + 1
    False, False -> count
  }
}

fn draw(count: Int) -> Nil {
  m5.start_write()
  m5.fill_screen(background)
  m5.set_text_size(2)
  m5.set_text_color(pink, background)
  m5.draw_center_string("Hello, Gleam!", 120, 12)
  m5.fill_round_rect(70, 44, 100, 50, 10, pink)
  m5.set_text_size(4)
  m5.set_text_color(background, pink)
  m5.draw_center_string(int.to_string(count), 120, 54)
  m5.set_text_size(1)
  m5.set_text_color(muted, background)
  m5.draw_center_string("A: +1   B: beep and reset", 120, 116)
  m5.end_write()
}

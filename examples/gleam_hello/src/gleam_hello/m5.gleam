//// Bindings to the atomvm_m5 functions this app uses. They are Erlang modules (m5, m5_display,
//// m5_btn_a, ...), provided by the firmware on the watch and by m5_emu in the emulator.
//// Drawing functions return the atom `ok`, typed here as Nil because the app ignores it.

/// Starts M5Unified. Call once, before anything else.
@external(erlang, "m5", "begin_")
pub fn begin(config: List(Nil)) -> Nil

/// Reads the buttons. The `was_*` flags below describe what happened since the previous update.
@external(erlang, "m5", "update")
pub fn update() -> Nil

@external(erlang, "m5_btn_a", "was_pressed")
pub fn a_was_pressed() -> Bool

@external(erlang, "m5_btn_b", "was_pressed")
pub fn b_was_pressed() -> Bool

/// A tone of `frequency` Hz for `ms` milliseconds.
@external(erlang, "m5_speaker", "tone")
pub fn tone(frequency: Int, ms: Int) -> Nil

/// 0 is portrait (135x240), 1 is landscape (240x135).
@external(erlang, "m5_display", "set_rotation")
pub fn set_rotation(rotation: Int) -> Nil

/// Batches the drawing calls up to `end_write` into one transfer to the screen.
@external(erlang, "m5_display", "start_write")
pub fn start_write() -> Nil

@external(erlang, "m5_display", "end_write")
pub fn end_write() -> Nil

/// Colours are 24-bit RGB integers, such as 0xFFAFF3.
@external(erlang, "m5_display", "fill_screen")
pub fn fill_screen(color: Int) -> Nil

@external(erlang, "m5_display", "fill_round_rect")
pub fn fill_round_rect(
  x: Int,
  y: Int,
  w: Int,
  h: Int,
  radius: Int,
  color: Int,
) -> Nil

/// Text size 1 is 6x8 pixels per character, 2 is 12x16, and so on.
@external(erlang, "m5_display", "set_text_size")
pub fn set_text_size(size: Int) -> Nil

/// Foreground and background colour of the text that follows.
@external(erlang, "m5_display", "set_text_color")
pub fn set_text_color(fg: Int, bg: Int) -> Nil

/// Draws `text` centred horizontally on `x`, with its top at `y`.
@external(erlang, "m5_display", "draw_center_string")
pub fn draw_center_string(text: String, x: Int, y: Int) -> Nil

@external(erlang, "timer", "sleep")
pub fn sleep(ms: Int) -> Nil

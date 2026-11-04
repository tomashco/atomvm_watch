//// Typed bindings to avm_scene and m5_scene.
////
//// A Gleam constructor compiles to an Erlang tuple tagged with its snake_case name, so
//// `Rect(x: 0, y: 0, w: 10, h: 10, color: 0xFF0000)` is exactly m5_scene's `{rect, 0, 0, 10, 10, 16711680}`
//// and a display list is a plain `List(Item)`. The few shapes Gleam can't express directly (a colour
//// or the atom `transparent`, the callback return tuples) come from gleam_scenes_ffi.erl.

/// One display list item. The first item in the list is drawn on top. See m5_scene/README.md.
pub type Item {
  Rect(x: Int, y: Int, w: Int, h: Int, color: Int)
  RoundedRect(x: Int, y: Int, w: Int, h: Int, radius: Int, color: Int)
  Circle(cx: Int, cy: Int, r: Int, color: Int)
  Line(x1: Int, y1: Int, x2: Int, y2: Int, thickness: Int, color: Int)
  Text(x: Int, y: Int, font: Font, fg: Int, bg: Background, text: String)
}

/// `Default16px` is 12x16 per character; `M5Font1` to `M5Font4` are 6x8 times 1 to 4.
pub type Font {
  Default16px
  M5Font1
  M5Font2
  M5Font3
  M5Font4
}

/// What is behind a text item: `transparent()` or `color(rgb)`.
pub type Background

@external(erlang, "gleam_scenes_ffi", "transparent")
pub fn transparent() -> Background

@external(erlang, "gleam_scenes_ffi", "identity")
pub fn color(rgb: Int) -> Background

/// m5_scene input events, `{button, Name, Event}` in Erlang.
pub type Input {
  Button(name: ButtonName, event: ButtonEvent)
}

pub type ButtonName {
  A
  B
  Pwr
}

pub type ButtonEvent {
  Pressed
  Hold
  Released
  Click
  DoubleClick
}

/// What a callback returns to avm_scene: the new state, and optionally a display list to push.
pub type Next(state)

/// Keep `state` and leave the screen as it is (`{noreply, State}`).
@external(erlang, "gleam_scenes_ffi", "noreply")
pub fn keep(state: state) -> Next(state)

/// Keep `state` and draw `items` (`{noreply, State, [{push, Items}]}`).
@external(erlang, "gleam_scenes_ffi", "push")
pub fn push(state: state, items: List(Item)) -> Next(state)

/// The reply to a gen_server call: `{reply, Reply, State}`.
pub type Reply(reply, state) {
  Reply(reply: reply, state: state)
}

pub type Pid

/// m5_scene options, `{rotation, R}` and `{background, Rgb}` in Erlang.
pub type SceneOption {
  Rotation(Int)
  Background(Int)
}

/// The options m5_scene hands to avm_scene (its display and input servers).
pub type SceneOptions

/// Starts m5_scene's display and input servers, linked to the caller.
@external(erlang, "m5_scene", "start_link")
pub fn start_m5_scene(options: List(SceneOption)) -> Result(SceneOptions, Nil)

/// An Erlang module name, for `start_avm_scene`.
pub type Module

@external(erlang, "gleam_scenes_ffi", "module")
pub fn module(name: String) -> Module

/// Starts the scene: avm_scene calls `module`'s init/1, handle_info/2, handle_input/4,
/// handle_call/3 and handle_cast/2, which must be `pub fn`s of that module.
@external(erlang, "avm_scene", "start_link")
pub fn start_avm_scene(
  module: Module,
  args: List(Nil),
  options: SceneOptions,
) -> Result(Pid, Nil)

@external(erlang, "m5", "begin_")
pub fn begin(config: List(Nil)) -> Nil

@external(erlang, "erlang", "self")
pub fn self() -> Pid

/// Sends `message` to `pid` after `ms` milliseconds; returns a timer reference.
@external(erlang, "erlang", "send_after")
pub fn send_after(ms: Int, pid: Pid, message: message) -> Reference

pub type Reference

@external(erlang, "erlang", "send")
pub fn send(pid: Pid, message: message) -> message

/// Blocks the calling process forever; AtomVM stops when the start function returns.
@external(erlang, "gleam_scenes_ffi", "wait_forever")
pub fn wait_forever() -> Nil

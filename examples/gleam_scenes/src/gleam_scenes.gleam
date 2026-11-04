//// Gleam example: an avm_scene scene drawn by m5_scene, with a typed display list.
//// A picks a swatch, B paints the circle with it, holding A resets.
//// Runs in the emulator and on the watch; build it with scripts/build-gleam-example.sh.

import gleam/list
import gleam_scenes/scene.{
  type Input, type Item, type Next, type Reply, A, B, Button, Circle,
  Default16px, Hold, M5Font1, Pressed, Reply, RoundedRect, Text,
}

const background = 0x101828

const pink = 0xFFAFF3

const empty = 0x3A3F4B

const swatches = [0xFFAFF3, 0x00FFFF, 0xFFFF00]

pub type State {
  State(selected: Int, chosen: Int)
}

pub type Message {
  Draw
}

/// The entry point AtomVM calls: packbeam makes this module the start module.
pub fn start() -> Nil {
  scene.begin([])
  let assert Ok(options) =
    scene.start_m5_scene([scene.Rotation(1), scene.Background(background)])
  let assert Ok(_) =
    scene.start_avm_scene(scene.module("gleam_scenes"), [], options)
  scene.wait_forever()
}

// avm_scene callbacks.

pub fn init(_args: List(Nil)) -> Result(State, Nil) {
  scene.send(scene.self(), Draw)
  Ok(State(selected: 0, chosen: empty))
}

pub fn handle_info(message: Message, state: State) -> Next(State) {
  case message {
    Draw -> scene.push(state, render(state))
  }
}

pub fn handle_input(
  event: Input,
  _ts: Int,
  _pid: scene.Pid,
  state: State,
) -> Next(State) {
  let next = case event {
    Button(A, Pressed) ->
      State(..state, selected: { state.selected + 1 } % list.length(swatches))
    Button(B, Pressed) -> State(..state, chosen: swatch(state.selected))
    Button(A, Hold) -> State(selected: 0, chosen: empty)
    _ -> state
  }
  case next == state {
    True -> scene.keep(state)
    False -> scene.push(next, render(next))
  }
}

pub fn handle_call(_message: a, _from: b, state: State) -> Reply(Nil, State) {
  Reply(Nil, state)
}

pub fn handle_cast(_message: a, state: State) -> Next(State) {
  scene.keep(state)
}

// The display list. The first item is drawn on top.

fn render(state: State) -> List(Item) {
  let tiles =
    list.index_map(swatches, fn(color, i) {
      tile(i, color, i == state.selected)
    })
    |> list.flatten
  [
    Text(8, 6, Default16px, pink, scene.transparent(), "Gleam scenes"),
    Circle(196, 64, 30, state.chosen),
    Text(
      8,
      120,
      M5Font1,
      0x9AA0A8,
      scene.transparent(),
      "A: next  B: paint  hold A: reset",
    ),
    ..tiles
  ]
}

/// A swatch, with a white frame behind it when selected.
fn tile(i: Int, color: Int, selected: Bool) -> List(Item) {
  let x = 10 + i * 50
  let swatch = RoundedRect(x, 44, 40, 40, 6, color)
  case selected {
    True -> [swatch, RoundedRect(x - 4, 40, 48, 48, 8, 0xFFFFFF)]
    False -> [swatch]
  }
}

fn swatch(i: Int) -> Int {
  case list.drop(swatches, i) {
    [color, ..] -> color
    [] -> empty
  }
}

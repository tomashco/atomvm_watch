# gleam_scenes

An `avm_scene` scene written in Gleam and drawn by `m5_scene`, with a typed display list. It runs in
the browser emulator and on the M5StickC Plus 2 with firmware v0.2.0 or later (the one
**Install runtime** installs from the site).

| Button | Action |
| --- | --- |
| A | select the next swatch |
| B | paint the circle with the selected swatch |
| hold A | reset |

```bash
scripts/build-gleam-example.sh gleam_scenes     # from the repo root, inside the devenv shell
```

That writes `examples/gleam_scenes/gleam_scenes.avm`: drop it on the emulator page, then use
**Install to device**, or flash it at `0x250000` with esptool as in `examples/gleam_hello`.

## How it works

A Gleam constructor compiles to an Erlang tuple tagged with its name in snake_case, which is the
shape of an `m5_scene` display list item:

```gleam
RoundedRect(x: 10, y: 44, w: 40, h: 40, radius: 6, color: 0xFFAFF3)
// is {rounded_rect, 10, 44, 40, 40, 6, 16756723}
Text(8, 6, Default16px, 0xFFAFF3, scene.transparent(), "Gleam scenes")
// is {text, 8, 6, default16px, 16756723, transparent, <<"Gleam scenes">>}
```

`src/gleam_scenes/scene.gleam` has the item, font and input types, and the bindings to `m5`,
`m5_scene` and `avm_scene`. Input events arrive as typed values too: `Button(A, Pressed)` is
`{button, a, pressed}`.

`src/gleam_scenes_ffi.erl` builds the few values Gleam can't express directly:

- callback results: `avm_scene` takes `{noreply, State}` or `{noreply, State, [{push, Items}]}`,
  one tag with two arities, so they are `scene.keep(state)` and `scene.push(state, items)`;
- a text background that is either a colour or the atom `transparent`;
- the module name passed to `avm_scene:start_link/3`.

The app module itself is the scene: its `pub fn`s `init`, `handle_info`, `handle_input`,
`handle_call` and `handle_cast` are the callbacks `avm_scene` calls. See `m5_scene/README.md` for the
display list items and `examples/gleam_hello` for how the app is built and packed.

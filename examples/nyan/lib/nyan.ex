defmodule Nyan do
  @moduledoc "Example: nyan cat flying across the screen with a rainbow trail, drawn with avm_scene through m5_scene."
  @background 0x003366

  def background, do: @background

  def start do
    :m5.begin_([])
    {:ok, scene_opts} = :m5_scene.start_link(rotation: 1, background: @background)
    {:ok, _pid} = :avm_scene.start_link(Nyan.App, [], scene_opts)

    receive do
      :stop -> :ok
    end
  end
end

defmodule Nyan.App do
  @moduledoc "avm_scene callbacks: a tick moves the cat and pushes the new display list. A pauses, B changes speed."
  alias Nyan.{Sky, Sprite}
  @tick_ms 50
  @speeds [2, 4, 6]

  def init(_args) do
    send(self(), :tick)

    {:ok,
     %{
       t: 0,
       x: -Sprite.width(),
       speed: 2,
       paused: false,
       frames: Sprite.frames(),
       segments: Sky.segments()
     }}
  end

  def handle_info(:tick, state) do
    :erlang.send_after(@tick_ms, self(), :tick)

    if state.paused do
      {:noreply, state}
    else
      state = advance(state)
      {:noreply, state, [{:push, render(state)}]}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def handle_input({:button, :a, :pressed}, _ts, _pid, state),
    do: {:noreply, %{state | paused: not state.paused}}

  def handle_input({:button, :b, :pressed}, _ts, _pid, state),
    do: {:noreply, %{state | speed: next_speed(state.speed, @speeds)}}

  def handle_input(_event, _ts, _pid, state), do: {:noreply, state}

  def handle_call(_msg, _from, state), do: {:reply, :ok, state}
  def handle_cast(_msg, state), do: {:noreply, state}

  defp advance(%{t: t, x: x, speed: speed} = state) do
    x = if x > 240, do: -Sprite.width(), else: x + speed
    %{state | t: t + 1, x: x}
  end

  defp next_speed(current, [current, next | _]), do: next
  defp next_speed(current, [_ | rest]) when rest != [], do: next_speed(current, rest)
  defp next_speed(_current, _), do: hd(@speeds)

  # The first item is on top: the cat, then its rainbow, then the stars and the hint.
  defp render(%{t: t, x: x, frames: [a, b], segments: segments}) do
    y = 44 + if rem(div(t, 3), 2) == 0, do: 0, else: 2
    frame = if rem(div(t, 2), 2) == 0, do: a, else: b

    [Sprite.item(x, y, frame) | Sky.rainbow(x + 10, y + 2, div(t, 4), segments)] ++
      Sky.stars(t) ++ [{:text, 4, 124, :m5_font1, 0x7090C0, :transparent, "A: pause   B: speed"}]
  end
end

defmodule Nyan.Sky do
  @moduledoc "The rainbow behind the cat and the twinkling stars."
  @stripes [0xFF0000, 0xFF9900, 0xFFFF00, 0x33FF00, 0x0099FF, 0x6633FF]
  @stripe 6
  @segment 16
  @trail 160
  @stars [{14, 12}, {70, 22}, {132, 8}, {200, 26}, {36, 104}, {104, 112}, {176, 98}, {226, 116}]

  # Segments sit on a fixed 16 px grid, so as the cat moves only the segment at its tail changes;
  # the wave flips every few ticks. A full segment is one image (two variants, converted once by
  # m5_scene and then cached); only the partial segments at the two ends are stripes of rects. Every
  # item costs m5_scene work each frame, so this keeps a long trail at about a dozen items, not 60.
  def rainbow(tip, top, phase, [up, down]) do
    first = max(0, div(max(tip - @trail, 0), @segment))
    last = div(tip - 1, @segment)

    :lists.append(
      for k <- :lists.seq(first, max(first, last)), do: segment(k, tip, top, phase, up, down)
    )
  end

  defp segment(k, tip, top, phase, up, down) do
    x0 = max(k * @segment, tip - @trail)
    x1 = min(k * @segment + @segment, tip)
    dy = if rem(k + phase, 2) == 0, do: 0, else: 2

    cond do
      x1 - x0 == @segment ->
        [{:image, x0, top, Nyan.background(), if(dy == 0, do: up, else: down)}]

      x1 > x0 ->
        for {color, i} <- :lists.zip(@stripes, :lists.seq(0, 5)),
            do: {:rect, x0, top + dy + i * @stripe, x1 - x0, @stripe, color}

      true ->
        []
    end
  end

  # The two full-segment images, 16 x 38: the six stripes at offset 0 (up) or 2 (down), the two
  # spare rows transparent (blended to the sky by the image's background).
  def segments, do: [segment_image(0), segment_image(2)]

  defp segment_image(dy) do
    rows =
      for y <- :lists.seq(0, 6 * @stripe + 1) do
        i = div(y - dy, @stripe)
        px = if y >= dy and i < 6, do: rgba(:lists.nth(i + 1, @stripes)), else: <<0, 0, 0, 0>>
        :binary.copy(px, @segment)
      end

    {:rgba8888, @segment, 6 * @stripe + 2, :erlang.list_to_binary(rows)}
  end

  defp rgba(c), do: <<div(c, 65536), rem(div(c, 256), 256), rem(c, 256), 255>>

  # Each star cycles through four sizes, out of step with the others.
  def stars(t) do
    for {{x, y}, i} <- :lists.zip(@stars, :lists.seq(0, length(@stars) - 1)) do
      star(x, y, rem(div(t, 3) + i, 4))
    end
    |> :lists.append()
  end

  defp star(x, y, 0), do: [{:rect, x, y, 1, 1, 0xFFFFFF}]
  defp star(x, y, 1), do: [{:rect, x - 1, y, 3, 1, 0xFFFFFF}, {:rect, x, y - 1, 1, 3, 0xFFFFFF}]
  defp star(x, y, 2), do: [{:rect, x - 2, y, 5, 1, 0xFFFFFF}, {:rect, x, y - 2, 1, 5, 0xFFFFFF}]

  defp star(x, y, 3),
    do: [
      {:rect, x - 3, y, 2, 1, 0xFFFFFF},
      {:rect, x + 2, y, 2, 1, 0xFFFFFF},
      {:rect, x, y - 3, 1, 2, 0xFFFFFF},
      {:rect, x, y + 2, 1, 2, 0xFFFFFF}
    ]
end

defmodule Nyan.Sprite do
  @moduledoc "The cat: two 34x20 pixel-art frames (legs and tail move), drawn at 2x."
  @scale 2

  @frame_a [
    "....kkkkkkkkkkkkkkkkkkkkk.........",
    "....ktttttttttttttttttttk.........",
    "....kttpppppppppppppppttk.........",
    "....ktppppppppmpppppppptk.........",
    "....ktpppmppppppppppkkptk...kk....",
    "....ktpppppppppppppmkgktk...kgk...",
    "....ktppppppppppppppkggkk...kggk..",
    "kk..ktppppppmpppppppkggkkkkkkggkk.",
    "ggk.ktppmppppppppppkgggggggggggggk",
    "gggkktpppppppppppmpkgggggggggggggk",
    "kgggktpppppppmpppppkggwkgggggwkggk",
    ".kggktpppppppppppppkggkkgggkgkkggk",
    "..kkktppppmppppppppkgggggggggggggk",
    "....ktpppppppppmpppkrrgkggkggkgrrk",
    "....ktpmpppppppppppkrrggkkgkkggrrk",
    "....kttppppppppppppkgggggggggggggk",
    "....ktttttttttttttttkkkkkkkkkkkkk.",
    "....kkkkkkkkkkkkkkkkkkkkk.........",
    "....kggkkggk....kggkkggk..........",
    "....kkkkkkkk....kkkkkkkk.........."
  ]

  @frame_b [
    "....kkkkkkkkkkkkkkkkkkkkk.........",
    "....ktttttttttttttttttttk.........",
    "....kttpppppppppppppppttk.........",
    "....ktppppppppmpppppppptk.........",
    "....ktpppmppppppppppkkptk...kk....",
    "....ktpppppppppppppmkgktk...kgk...",
    "....ktppppppppppppppkggkk...kggk..",
    "....ktppppppmpppppppkggkkkkkkggkk.",
    "..kkktppmppppppppppkgggggggggggggk",
    ".kggktpppppppppppmpkgggggggggggggk",
    "kgggktpppppppmpppppkggwkgggggwkggk",
    "gggkktpppppppppppppkggkkgggkgkkggk",
    "ggk.ktppppmppppppppkgggggggggggggk",
    "kk..ktpppppppppmpppkrrgkggkggkgrrk",
    "....ktpmpppppppppppkrrggkkgkkggrrk",
    "....kttppppppppppppkgggggggggggggk",
    "....ktttttttttttttttkkkkkkkkkkkkk.",
    "....kkkkkkkkkkkkkkkkkkkkk.........",
    ".....kggkkggk....kggkkggk.........",
    ".....kkkkkkkk....kkkkkkkk........."
  ]

  def width, do: 34 * @scale

  # Built once, at init: two {rgba8888, 34, 20, Pixels} images.
  def frames, do: [image(@frame_a), image(@frame_b)]

  def item(x, y, image),
    do:
      {:scaled_cropped_image, x, y, 34 * @scale, 20 * @scale, :transparent, 0, 0, @scale, @scale,
       [], image}

  defp image(rows) do
    pixels = for row <- rows, <<c <- row>>, do: color(c)
    {:rgba8888, 34, 20, :erlang.list_to_binary(pixels)}
  end

  defp color(?k), do: <<0, 0, 0, 255>>
  defp color(?t), do: <<255, 204, 153, 255>>
  defp color(?p), do: <<255, 153, 255, 255>>
  defp color(?m), do: <<255, 51, 153, 255>>
  defp color(?g), do: <<153, 153, 153, 255>>
  defp color(?w), do: <<255, 255, 255, 255>>
  defp color(?r), do: <<255, 153, 153, 255>>
  defp color(_), do: <<0, 0, 0, 0>>
end

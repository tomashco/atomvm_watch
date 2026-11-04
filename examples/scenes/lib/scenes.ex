defmodule Scenes do
  @moduledoc "Example: a menu scene and a detail scene, drawn with avm_scene through m5_scene."
  @background 0x101828

  def start do
    :m5.begin_([])
    {:ok, scene_opts} = :m5_scene.start_link(rotation: 1, background: @background)
    {:ok, _pid} = :avm_scene.start_link(Scenes.App, [], scene_opts)

    receive do
      :stop -> :ok
    end
  end
end

defmodule Scenes.App do
  @moduledoc "avm_scene callbacks: keeps the state and pushes the current screen's display list."
  alias Scenes.{Detail, Menu}

  def init(_args) do
    send(self(), :draw)
    {:ok, %{screen: :menu, selected: 0, icons: Scenes.Icons.all()}}
  end

  def handle_info(:draw, state), do: {:noreply, state, [{:push, render(state)}]}
  def handle_info(_msg, state), do: {:noreply, state}

  def handle_input({:button, button, event}, _ts, _pid, state) do
    case next(state, button, event) do
      ^state -> {:noreply, state}
      new_state -> {:noreply, new_state, [{:push, render(new_state)}]}
    end
  end

  def handle_input(_event, _ts, _pid, state), do: {:noreply, state}

  def handle_call(_msg, _from, state), do: {:reply, :ok, state}
  def handle_cast(_msg, state), do: {:noreply, state}

  defp next(%{screen: :menu} = s, :a, :pressed), do: %{s | selected: rem(s.selected + 1, Menu.count())}
  defp next(%{screen: :menu} = s, :b, :pressed), do: %{s | screen: :detail}
  defp next(%{screen: :detail} = s, :b, :pressed), do: %{s | screen: :menu}
  defp next(%{screen: :detail} = s, :a, :hold), do: %{s | screen: :menu}
  defp next(s, _button, _event), do: s

  defp render(%{screen: :menu} = s), do: Menu.render(s.selected, s.icons)
  defp render(%{screen: :detail} = s), do: Detail.render(s.selected)
end

defmodule Scenes.Menu do
  @moduledoc "The menu: a title and three entries; the selected one is highlighted with inverted text."
  @entries ["Clock", "Timer", "Settings"]
  @top 32
  @row 30

  def count, do: length(@entries)
  def entries, do: @entries

  # The first item is on top: title, each entry's text and icon, then the highlight below them.
  def render(selected, icons) do
    # AtomVM's Enum has no with_index/1 or zip/2: walk the indices.
    rows =
      Enum.flat_map(:lists.seq(0, count() - 1), fn i ->
        row(Enum.at(@entries, i), i, i == selected, Enum.at(icons, i))
      end)

    [{:text, 8, 6, :default16px, 0xFFFFFF, :transparent, "Scenes"} | rows] ++
      [{:rounded_rect, 4, @top + selected * @row, 232, 26, 6, 0xFFFFFF}]
  end

  defp row(name, i, selected?, icon) do
    y = @top + i * @row
    color = if selected?, do: 0x000000, else: 0xFFFFFF
    [{:text, 36, y + 5, :default16px, color, :transparent, name}, {:image, 12, y + 5, :transparent, icon}]
  end
end

defmodule Scenes.Detail do
  @moduledoc "The detail screen of a menu entry: its name and a small drawing."
  def render(selected) do
    [
      {:text, 8, 6, :default16px, 0xFFFFFF, :transparent, Enum.at(Scenes.Menu.entries(), selected)},
      {:text, 8, 112, :m5_font1, 0xA0A0A0, :transparent, "B: back   hold A: back"},
      {:circle, 120, 60, 30, 0x00FFFF},
      {:line, 40, 100, 200, 100, 1, 0xFFFF00}
    ]
  end
end

defmodule Scenes.Icons do
  @moduledoc "16x16 RGBA discs, transparent outside the disc. Built once, at init."
  import Bitwise
  @colors [0xFF0000, 0x00FF00, 0x0000FF]

  def all, do: Enum.map(@colors, &disc/1)

  def disc(rgb) do
    on = <<(rgb >>> 16) &&& 0xFF, (rgb >>> 8) &&& 0xFF, rgb &&& 0xFF, 255>>
    off = <<0, 0, 0, 0>>

    pixels =
      for y <- 0..15, x <- 0..15 do
        dx = 2 * x - 15
        dy = 2 * y - 15
        if dx * dx + dy * dy <= 225, do: on, else: off
      end

    {:rgba8888, 16, 16, :erlang.list_to_binary(pixels)}
  end
end

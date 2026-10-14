defmodule Scenes do
  @moduledoc "Probe (Task 1): avm_scene from Hex draws one rect. Replaced by the m5_scene app in Task 10."

  def start do
    :m5.begin_([])
    :m5_display.set_rotation(1)
    {:ok, _pid} = :avm_scene.start_link(Scenes.Probe, [], display_server: {Scenes.ProbeDisplay, nil})

    receive do
      :stop -> :ok
    end
  end
end

defmodule Scenes.Probe do
  @moduledoc false
  def init(_args) do
    send(self(), :draw)
    {:ok, nil}
  end

  def handle_info(:draw, state), do: {:noreply, state, [{:push, [{:rect, 10, 10, 50, 30, 0x00FF00}]}]}
end

defmodule Scenes.ProbeDisplay do
  @moduledoc false
  # Stands in for m5_scene_display until Task 10: draws rect items, last item first.
  def call(_display, {:update, items}) do
    for {:rect, x, y, w, h, c} <- Enum.reverse(items), do: :m5_display.fill_rect(x, y, w, h, c)
    :ok
  end
end

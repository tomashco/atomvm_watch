defmodule Clock do
  @moduledoc "Reference app: clock face, button-driven screens, beep and LED. Runs in the emulator and on the watch."
  @led 19
  @screens [:clock, :buttons, :about]

  def start do
    :m5.begin_([])
    :m5_display.set_rotation(1)
    :gpio.set_pin_mode(@led, :output)
    loop(%{screen: 0, led: false, last_draw: 0, boot: :erlang.monotonic_time(:second)})
  end

  defp loop(state) do
    :timer.sleep(10)
    :m5.update()
    state = state |> handle_a() |> handle_b() |> handle_pwr()
    state = maybe_draw(state)
    loop(state)
  end

  defp handle_a(state) do
    if :m5_btn_a.was_pressed(),
      do: %{state | screen: rem(state.screen + 1, length(@screens)), last_draw: 0},
      else: state
  end

  defp handle_b(state) do
    if :m5_btn_b.was_pressed() do
      :m5_speaker.tone(1800, 80)
      led = not state.led
      :gpio.digital_write(@led, if(led, do: :high, else: :low))
      %{state | led: led, last_draw: 0}
    else
      state
    end
  end

  defp handle_pwr(state) do
    cond do
      :m5_btn_pwr.was_pressed() ->
        :m5_display.sleep()
        state

      :m5_btn_pwr.was_released() ->
        :m5_display.wakeup()
        %{state | last_draw: 0}

      true ->
        state
    end
  end

  defp maybe_draw(%{last_draw: last} = state) do
    now = :erlang.monotonic_time(:second)

    if now != last do
      draw(Enum.at(@screens, state.screen), state, now)
      %{state | last_draw: now}
    else
      state
    end
  end

  defp draw(:clock, state, now) do
    secs = now - state.boot

    text =
      :io_lib.format("~2..0B:~2..0B:~2..0B", [div(secs, 3600), rem(div(secs, 60), 60), rem(secs, 60)])
      |> :erlang.iolist_to_binary()

    :m5_display.start_write()
    :m5_display.fill_screen(0x000000)
    :m5_display.set_text_size(4)
    :m5_display.draw_center_string(text, div(:m5_display.width(), 2), 40)
    :m5_display.set_text_size(1)
    :m5_display.set_cursor(4, 120)
    :m5_display.print("A: next  B: beep+LED  PWR: sleep")
    :m5_display.end_write()
  end

  defp draw(:buttons, state, _now) do
    :m5_display.start_write()
    :m5_display.fill_screen(0x102040)
    :m5_display.set_text_size(2)
    :m5_display.set_cursor(0, 0)
    :m5_display.println("Buttons")
    :m5_display.set_text_size(1)
    :m5_display.println("A pressed: #{:m5_btn_a.is_pressed()}")
    :m5_display.println("B pressed: #{:m5_btn_b.is_pressed()}")
    :m5_display.println("LED: #{state.led}")
    :m5_display.fill_rect(200, 100, 30, 30, if(state.led, do: 0xFF0000, else: 0x404040))
    :m5_display.end_write()
  end

  defp draw(:about, _state, _now) do
    :m5_display.start_write()
    :m5_display.fill_screen(0x203010)
    :m5_display.set_text_size(2)
    :m5_display.set_cursor(0, 0)
    :m5_display.println("atomvm_watch")
    :m5_display.set_text_size(1)
    :m5_display.println("board: #{:m5.get_board()}")
    :m5_display.println("#{:m5_display.width()}x#{:m5_display.height()}")
    :m5_display.end_write()
  end
end

defmodule Mix.Tasks.M5.Emulate do
  use Mix.Task
  @shortdoc "Pack the app and open it in the atomvm_watch emulator, rebuilding on change"
  @moduledoc """
  Runs `mix atomvm.packbeam`, serves the emulator page with the headers AtomVM needs, opens the
  browser, and re-packs when files under lib/ change. The page polls `/__version` and reloads.

      mix m5.emulate [--port 4174] [--web-dir path/to/web/dist] [--no-open]

  Set `M5_EMU_NO_OPEN=1` to never launch a browser.
  """
  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [port: :integer, web_dir: :string, open: :boolean])
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:bandit)
    web_dir = opts[:web_dir] || Application.app_dir(:m5_emu_mix, "priv/web")

    unless File.exists?(Path.join(web_dir, "index.html")),
      do: Mix.raise("emulator page not found in #{web_dir}; run scripts/build-web.sh or pass --web-dir")

    avm = pack!()
    {:ok, pid} = M5EmuMix.Server.start(port: opts[:port] || 4174, web_dir: web_dir, avm: avm)
    port = M5EmuMix.Server.port(pid)
    url = "http://localhost:#{port}/?dev=1&avm=http://localhost:#{port}/app.avm"
    Mix.shell().info("emulator at #{url}")

    if Keyword.get(opts, :open, true) and System.get_env("M5_EMU_NO_OPEN") in [nil, "", "0"],
      do: System.cmd(open_cmd(), [url])

    watch_loop(mtimes())
  end

  defp pack! do
    Mix.Task.rerun("atomvm.packbeam")
    Path.join(File.cwd!(), "#{Mix.Project.config()[:app]}.avm")
  end

  defp mtimes, do: Path.wildcard("lib/**/*.{ex,erl}") |> Map.new(&{&1, File.stat!(&1).mtime})

  defp watch_loop(seen) do
    Process.sleep(500)
    now = mtimes()

    if now != seen do
      Mix.shell().info("change detected, repacking...")

      try do
        pack!()
      rescue
        e -> Mix.shell().error(Exception.message(e))
      end
    end

    watch_loop(now)
  end

  defp open_cmd do
    case :os.type() do
      {:unix, :darwin} -> "open"
      {:unix, _} -> "xdg-open"
      _ -> "start"
    end
  end
end

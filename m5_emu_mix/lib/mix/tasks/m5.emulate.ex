defmodule Mix.Tasks.M5.Emulate do
  use Mix.Task
  @shortdoc "Pack the app and open it in the atomvm_watch emulator, rebuilding on change"
  @moduledoc """
  Compiles and packs the app with `mix atomvm.packbeam`, serves the emulator page with the headers
  AtomVM needs, opens the browser, and rebuilds when files under lib/ change. The page polls
  `/__version` (a counter bumped after each successful pack) and reloads.

      mix m5.emulate [--port 4174] [--web-dir path/to/web/dist] [--no-open]

  Set `M5_EMU_NO_OPEN=1` to never launch a browser. A failed rebuild is reported and the previous
  app keeps being served.
  """
  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [port: :integer, web_dir: :string, open: :boolean])
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:bandit)
    web_dir = opts[:web_dir] || Application.app_dir(:m5_emu_mix, "priv/web")

    unless File.exists?(Path.join(web_dir, "index.html")),
      do: Mix.raise("emulator page not found in #{web_dir}; run scripts/build-web.sh or pass --web-dir")

    served = Path.join(Mix.Project.build_path(), "m5_emu/app.avm")
    version = M5EmuMix.Version.new()

    case M5EmuMix.Builder.rebuild(served, version) do
      :ok -> :ok
      {:error, msg} -> Mix.raise("initial build failed: #{msg}")
    end

    {:ok, pid} = M5EmuMix.Server.start(port: opts[:port] || 4174, web_dir: web_dir, avm: served, version: version)
    port = M5EmuMix.Server.port(pid)
    url = "http://127.0.0.1:#{port}/?dev=1&avm=http://127.0.0.1:#{port}/app.avm"
    Mix.shell().info("emulator at #{url}")

    if Keyword.get(opts, :open, true) and System.get_env("M5_EMU_NO_OPEN") in [nil, "", "0"],
      do: open(url)

    loop(mtimes(), served, version)
  end

  defp mtimes do
    Path.wildcard("lib/**/*.{ex,erl}")
    |> Enum.flat_map(fn f ->
      # An editor's atomic save can remove the file between wildcard and stat.
      case File.stat(f, time: :posix) do
        {:ok, s} -> [{f, {s.mtime, s.size}}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp loop(seen, served, version) do
    Process.sleep(500)
    now = mtimes()

    if now != seen do
      Mix.shell().info("change detected, repacking...")

      case M5EmuMix.Builder.rebuild(served, version) do
        :ok -> Mix.shell().info("repacked")
        {:error, msg} -> Mix.shell().error("build failed (keeping the previous app): #{msg}")
      end
    end

    loop(now, served, version)
  end

  defp open(url) do
    {cmd, args} =
      case :os.type() do
        {:unix, :darwin} -> {"open", [url]}
        {:unix, _} -> {"xdg-open", [url]}
        _ -> {"cmd", ["/c", "start", "", url]}
      end

    try do
      case System.cmd(cmd, args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        _ -> Mix.shell().info("could not open a browser; open #{url}")
      end
    rescue
      _ -> Mix.shell().info("could not open a browser; open #{url}")
    end
  end
end

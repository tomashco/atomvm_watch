defmodule M5EmuMix.Server do
  @moduledoc false
  def start(opts) do
    opts = Keyword.put_new_lazy(opts, :version, &M5EmuMix.Version.new/0)

    Bandit.start_link(
      plug: {M5EmuMix.Plug, opts},
      port: Keyword.get(opts, :port, 4174),
      ip: {127, 0, 0, 1},
      startup_log: false
    )
  end

  def port(pid) do
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    port
  end
end

defmodule M5EmuMix.Plug do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: Map.new(opts)

  @impl true
  def call(conn, %{web_dir: dir, avm: avm, version: version}) do
    conn =
      conn
      |> put_resp_header("cross-origin-opener-policy", "same-origin")
      |> put_resp_header("cross-origin-embedder-policy", "require-corp")
      |> put_resp_header("cross-origin-resource-policy", "cross-origin")
      |> put_resp_header("cache-control", "no-store")

    case conn.request_path do
      "/app.avm" ->
        serve(conn, avm, "application/octet-stream")

      "/__version" ->
        conn |> put_resp_content_type("text/plain") |> send_resp(200, to_string(M5EmuMix.Version.get(version)))

      path ->
        decoded = URI.decode(path)
        rel = if decoded == "/", do: "index.html", else: String.trim_leading(decoded, "/")

        case Path.safe_relative(rel) do
          {:ok, safe} -> serve(conn, Path.join(dir, safe), MIME.from_path(safe))
          :error -> send_resp(conn, 404, "not found")
        end
    end
  end

  defp serve(conn, file, type) do
    if File.regular?(file) do
      conn |> put_resp_content_type(type, nil) |> send_file(200, file)
    else
      send_resp(conn, 404, "not found")
    end
  end
end

defmodule M5EmuMix.ServerTest do
  use ExUnit.Case
  import Plug.Test

  setup do
    dir = Path.join(System.tmp_dir!(), "m5emu_#{System.unique_integer([:positive])}")
    web = Path.join(dir, "web")
    File.mkdir_p!(web)
    File.write!(Path.join(web, "index.html"), "<h1>hi</h1>")
    File.write!(Path.join(web, "a.wasm"), <<0, 97, 115, 109>>)
    File.write!(Path.join(web, "a.mjs"), "export {}")
    File.write!(Path.join(dir, "secret.txt"), "secret")
    avm = Path.join(dir, "app.avm")
    File.write!(avm, <<1, 2, 3>>)
    version = M5EmuMix.Version.new()
    {:ok, pid} = M5EmuMix.Server.start(port: 0, web_dir: web, avm: avm, version: version)
    plug_opts = M5EmuMix.Plug.init(web_dir: web, avm: avm, version: version)
    %{port: M5EmuMix.Server.port(pid), avm: avm, version: version, plug_opts: plug_opts, dir: dir}
  end

  defp get(port, path) do
    {:ok, {{_, status, _}, headers, body}} =
      :httpc.request(:get, {~c"http://127.0.0.1:#{port}#{path}", []}, [], body_format: :binary)

    {status, Map.new(headers, fn {k, v} -> {to_string(k), to_string(v)} end), body}
  end

  defp call(path, opts), do: M5EmuMix.Plug.call(conn(:get, path), opts)

  test "serves static files with isolation headers", %{port: port} do
    {200, h, body} = get(port, "/index.html")
    assert body == "<h1>hi</h1>"
    assert h["cross-origin-opener-policy"] == "same-origin"
    assert h["cross-origin-embedder-policy"] == "require-corp"
  end

  test "serves the app over HTTP", %{port: port} do
    {200, _, <<1, 2, 3>>} = get(port, "/app.avm")
  end

  test "content types for wasm and mjs", %{plug_opts: o} do
    assert ["application/wasm" <> _] = Plug.Conn.get_resp_header(call("/a.wasm", o), "content-type")
    assert [js] = Plug.Conn.get_resp_header(call("/a.mjs", o), "content-type")
    assert js =~ "javascript"
  end

  test "404 on a missing file", %{plug_opts: o} do
    assert call("/nope.js", o).status == 404
  end

  test "does not escape web_dir", %{plug_opts: o} do
    for p <- ["/../secret.txt", "/%2e%2e/secret.txt", "/..%2fsecret.txt", "/a/../../secret.txt"] do
      c = call(p, o)
      assert c.status == 404, "#{p} gave #{c.status}"
      refute c.resp_body == "secret"
    end
  end

  test "/__version is the counter, bumped only by successful builds", %{plug_opts: o, version: v, dir: dir} do
    served = Path.join(dir, "out/app.avm")
    built = Path.join(dir, "built.avm")
    File.write!(built, <<9, 9>>)
    assert call("/__version", o).resp_body == "0"

    assert :ok = M5EmuMix.Builder.rebuild(served, v, fn -> {:ok, built} end)
    assert call("/__version", o).resp_body == "1"
    assert File.read!(served) == <<9, 9>>
    refute File.exists?(served <> ".tmp")

    assert {:error, "boom"} = M5EmuMix.Builder.rebuild(served, v, fn -> {:error, "boom"} end)
    assert {:error, msg} = M5EmuMix.Builder.rebuild(served, v, fn -> raise CompileError, description: "bad" end)
    assert msg =~ "bad"
    assert {:error, _} = M5EmuMix.Builder.rebuild(served, v, fn -> throw(:x) end)
    assert call("/__version", o).resp_body == "1"
    assert File.read!(served) == <<9, 9>>
  end
end

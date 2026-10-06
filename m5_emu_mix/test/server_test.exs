defmodule M5EmuMix.ServerTest do
  use ExUnit.Case
  setup do
    dir = Path.join(System.tmp_dir!(), "m5emu_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir); File.write!(Path.join(dir, "index.html"), "<h1>hi</h1>")
    avm = Path.join(dir, "app.avm"); File.write!(avm, <<1, 2, 3>>)
    {:ok, pid} = M5EmuMix.Server.start(port: 0, web_dir: dir, avm: avm)
    port = M5EmuMix.Server.port(pid)
    %{port: port, avm: avm}
  end
  defp get(port, path) do
    {:ok, {{_, status, _}, headers, body}} = :httpc.request(:get, {~c"http://127.0.0.1:#{port}#{path}", []}, [], body_format: :binary)
    {status, Map.new(headers, fn {k, v} -> {to_string(k), to_string(v)} end), body}
  end
  test "serves static files with isolation headers", %{port: port} do
    {200, h, body} = get(port, "/index.html")
    assert body == "<h1>hi</h1>"
    assert h["cross-origin-opener-policy"] == "same-origin"
    assert h["cross-origin-embedder-policy"] == "require-corp"
  end
  test "serves the app and a version that changes on rewrite", %{port: port, avm: avm} do
    {200, _, <<1, 2, 3>>} = get(port, "/app.avm")
    {200, _, v1} = get(port, "/__version")
    Process.sleep(1100); File.write!(avm, <<4>>)
    {200, _, v2} = get(port, "/__version")
    assert v1 != v2
  end
  test "does not escape web_dir", %{port: port} do
    {status, _, _} = get(port, "/..%2f..%2fetc/passwd")
    assert status == 404
  end
end

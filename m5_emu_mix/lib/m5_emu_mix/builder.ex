defmodule M5EmuMix.Version do
  @moduledoc false
  # A counter shared between the build loop and the HTTP plug. Bumped only after a successful pack.
  def new, do: :atomics.new(1, signed: false)
  def get(ref), do: :atomics.get(ref, 1)
  def bump(ref), do: :atomics.add_get(ref, 1, 1)
end

defmodule M5EmuMix.Builder do
  @moduledoc false
  alias M5EmuMix.Version

  @doc """
  Runs `build_fun` (which returns `{:ok, built_avm_path}` or `{:error, message}`, or raises), then
  publishes the result to `served` through a temp file and a rename, so `/app.avm` is never
  half-written, and bumps the version. On failure nothing is published and the version is untouched.
  """
  def rebuild(served, version, build_fun \\ &default_build/0) do
    result =
      try do
        build_fun.()
      rescue
        e -> {:error, Exception.format(:error, e, [])}
      catch
        kind, reason -> {:error, Exception.format(kind, reason, [])}
      end

    case result do
      {:ok, built} ->
        File.mkdir_p!(Path.dirname(served))
        tmp = served <> ".tmp"
        File.cp!(built, tmp)
        File.rename!(tmp, served)
        Version.bump(version)
        :ok

      {:error, message} ->
        {:error, message}
    end
  end

  # exatomvm's atomvm.packbeam only packs compile_path, so compile first; it returns :error rather
  # than raising when the pack fails.
  defp default_build do
    for t <- ["compile", "compile.all", "compile.elixir", "compile.erlang", "compile.app"],
        do: Mix.Task.reenable(t)

    case Mix.Task.run("compile") do
      {:error, _} ->
        {:error, "compilation failed"}

      _ ->
        Mix.Task.reenable("atomvm.packbeam")

        case Mix.Task.run("atomvm.packbeam") do
          {:ok, _} -> {:ok, Path.join(File.cwd!(), "#{Mix.Project.config()[:app]}.avm")}
          other -> {:error, "atomvm.packbeam failed: #{inspect(other)}"}
        end
    end
  end
end

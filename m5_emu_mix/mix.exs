defmodule M5EmuMix.MixProject do
  use Mix.Project

  def project do
    [
      app: :m5_emu_mix,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: false,
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:bandit, "~> 1.6"},
      {:plug, "~> 1.16"}
    ]
  end
end

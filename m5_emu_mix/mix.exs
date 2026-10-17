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

  def application do
    # inets (httpc) is only used by the tests.
    [extra_applications: [:logger] ++ if(Mix.env() == :test, do: [:inets], else: [])]
  end

  defp deps do
    [
      {:bandit, "~> 1.6"},
      {:plug, "~> 1.16"}
    ]
  end
end

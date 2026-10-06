defmodule Clock.MixProject do
  use Mix.Project

  def project do
    [
      app: :clock,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: false,
      deps: deps(),
      atomvm: [start: Clock, esp32_flash_offset: 0x250000]
    ]
  end

  def application, do: [extra_applications: []]

  defp deps do
    [
      {:exatomvm,
       git: "https://github.com/atomvm/exatomvm.git",
       ref: "a99323a1054adda1ec00e9997bc41bc7317a3826",
       runtime: false},
      {:atomvm, "~> 0.7.0-beta.0", runtime: false},
      {:atomvm_m5,
       git: "https://github.com/pguyot/atomvm_m5.git",
       ref: "968508c77c90af5a0109bcd7f0e28a5fa8624c02",
       manager: :rebar3}
    ]
  end
end

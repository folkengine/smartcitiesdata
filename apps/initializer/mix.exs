defmodule Initializer.MixProject do
  use Mix.Project

  def project do
    [
      app: :initializer,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:retry, "~> 0.13.0"},
      {:credo, "~> 1.3", only: [:dev]}
    ]
  end
end
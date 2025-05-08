defmodule Xander.MixProject do
  use Mix.Project

  @description "An Elixir library for communicating with a Cardano node"
  @source_url "https://github.com/wowica/xander"
  @version "0.2.0"

  def project do
    [
      app: :xander,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Xander",
      source_url: @source_url,
      description: @description,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl]
    ]
  end

  defp deps do
    [
      {:blake2, "~> 1.0"},
      {:cbor, "~> 1.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    An Elixir library for connecting to a Cardano node.
    """
  end

  defp package do
    [
      name: "xander",
      maintainers: ["Carlos Souza", "Dave Miner"],
      files: ~w(lib .formatter.exs mix.exs README*),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/wowica/xander"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end

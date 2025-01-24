defmodule Xander.MixProject do
  use Mix.Project

  def project do
    [
      app: :xander,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Xander",
      source_url: "https://github.com/wowica/xander",
      docs: [
        main: "Xander",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl]
    ]
  end

  defp deps do
    [
      {:cbor, "~> 1.0"},
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
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/wowica/xander"}
    ]
  end
end

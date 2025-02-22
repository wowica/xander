defmodule Xander.Config do
  @moduledoc """
  This module provides functions to configure the Xander client.

  ## Examples

  ### Connecting to a local Cardano node:

      # Use default configuration
      path = "/tmp/cardano-node.socket"
      config = Xander.Config.default_config!(path)
      {:ok, pid} = Xander.Query.start_link(config)

      # Or customize the configuration
      path = "/tmp/cardano-node.socket"
      config = Xander.Config.default_config!(path, :preview)

      {:ok, pid} = Xander.Query.start_link(config)

  ### Connecting to a Demeter node:

      # Configure for Demeter
      url = "https://your-demeter-url.demeter.run"
      config = Xander.Config.demeter_config!(url)

      {:ok, pid} = Xander.Query.start_link(config)

      # Query the current era
      {:ok, current_era} = Xander.Query.query(pid, :get_current_era)
  """

  @doc """
  Returns the default configuration for connecting to a Cardano node.
  """
  def default_config!(path, network \\ :mainnet) do
    [
      network: network,
      path: path,
      port: 0,
      type: :socket
    ]
    |> validate_config!()
  end

  @doc """
  Returns configuration for connecting to a Demeter node.
  """
  def demeter_config!(url, opts \\ []) do
    port = Keyword.get(opts, :port, 9443)
    network = Keyword.get(opts, :network, :mainnet)

    [
      network: network,
      path: url,
      port: port,
      type: :ssl
    ]
    |> validate_config!()
  end

  # Validates and normalizes the configuration options.
  defp validate_config!(opts) do
    if opts[:network] not in [:mainnet, :preprod, :preview, :sanchonet, :yaci_devkit] do
      raise ArgumentError,
            "network must be :mainnet, :preprod, :preview, :sanchonet, or :yaci_devkit"
    end

    if opts[:type] not in [:socket, :ssl] do
      raise ArgumentError, "type must be :socket or :ssl"
    end

    opts
  end
end

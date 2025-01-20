defmodule Xander.Handshake.Proposal do
  @moduledoc """
  Builds handshake messages for node-to-client communication.
  """

  @type network_type :: :mainnet | :preprod | :preview | :sanchonet

  @network_magic [
    mainnet: 764_824_073,
    preprod: 1,
    preview: 2,
    sanchonet: 4
  ]

  @version_numbers %{
    9 => 32777,
    10 => 32778,
    11 => 32779,
    12 => 32780,
    13 => 32781,
    14 => 32782,
    15 => 32783,
    16 => 32784,
    17 => 32785
  }

  @doc """
  Version numbers must be unique and appear in ascending order.
  """
  @spec version_message([integer()], network_type) :: binary()
  def version_message(versions, network) do
    payload =
      [
        # msgProposeVersions
        0,
        build_version_fragments(versions |> Enum.sort(), network)
      ]
      |> CBOR.encode()

    header(payload) <> payload
  end

  defp build_version_fragments(versions, network),
    do:
      Enum.reduce(versions, %{}, fn version, acc ->
        Map.merge(acc, version_fragment(version, network))
      end)

  defp version_fragment(version, network) when version >= 15,
    do: %{@version_numbers[version] => [@network_magic[network], false]}

  defp version_fragment(version, network),
    do: %{@version_numbers[version] => @network_magic[network]}

  # middle 16 bits are: 1 bit == 0 for initiator and 15 bits for the mini protocol ID (0)
  defp header(payload),
    do: <<header_timestamp()::32>> <> <<0, 0>> <> <<byte_size(payload)::unsigned-16>>

  # Returns the lower 32 bits of the system's monotonic time in microseconds
  defp header_timestamp(),
    do:
      System.monotonic_time(:microsecond)
      |> Bitwise.band(0xFFFFFFFF)
end

defmodule Xander.Messages do
  @moduledoc """
  This module returns protocol messages ready to be sent to the server.
  """

  @mini_protocols %{
    handshake: 0,
    chain_sync: 5,
    local_tx_submission: 6,
    local_state_query: 7,
    local_tx_monitor: 9
  }

  @get_current_block_height [2]
  @get_current_era [0, [2, [1]]]

  def msg_acquire do
    header = [<<0, 0, 44, 137, 0, 7, 0, 2>>]
    payload = [<<129, 8>>]

    [header | payload]
  end

  def msg_release do
    header = [<<0, 0, 167, 211, 0, 7, 0, 2>>]
    payload = [<<129, 5>>]

    [header | payload]
  end

  @doc """
  Builds a static query to get the current era.

  Payload CBOR: [3, [0, [2, [1]]]]
  Payload Bitstring: <<130, 3, 130, 0, 130, 2, 129, 1>>

  ## Examples

    iex> <<_timestamp::32, msg::binary>> = Xander.Messages.get_current_era()
    iex> msg
    <<0, 7, 0, 8, 130, 3, 130, 0, 130, 2, 129, 1>>
  """
  @spec get_current_era() :: binary()
  def get_current_era do
    payload = build_query(@get_current_era)
    bitstring_payload = CBOR.encode(payload)

    header(@mini_protocols.local_state_query, bitstring_payload) <> bitstring_payload
  end

  @doc """
  Builds a static query to get the current block height.

  Payload CBOR: [3, [2]]
  Payload Bitstring: <<130, 3, 129, 2>>

  ## Examples

    iex> <<_timestamp::32, msg::binary>> = Xander.Messages.get_current_block_height()
    iex> msg
    <<0, 7, 0, 4, 130, 3, 129, 2>>
  """
  @spec get_current_block_height() :: binary()
  def get_current_block_height do
    payload = build_query(@get_current_block_height)
    bitstring_payload = CBOR.encode(payload)

    header(@mini_protocols.local_state_query, bitstring_payload) <> bitstring_payload
  end

  defp build_query(query), do: [3, query]

  # middle 16 bits are: 1 bit == 0 for initiator and 15 bits for the mini protocol ID
  defp header(mini_protocol_id, payload),
    do:
      <<header_timestamp()::32>> <> <<0, mini_protocol_id>> <> <<byte_size(payload)::unsigned-16>>

  # Returns the lower 32 bits of the system's monotonic time in microseconds
  defp header_timestamp,
    do:
      System.monotonic_time(:microsecond)
      |> Bitwise.band(0xFFFFFFFF)

  def get_epoch_number do
    header = [<<0, 0, 117, 154, 0, 7, 0, 10>>]
    payload = [<<130, 3, 130, 0, 130, 0, 130, 6, 129, 1>>]
    [header | payload]
  end
end

defmodule Xander.Messages do
  @moduledoc """
  This module builds protocol messages ready to be sent to the server.
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
  @get_epoch_number [0, [0, [6, [1]]]]
  @get_current_tip [3]

  # See the CDDL for details on mapping of messages to numbers.
  # https://github.com/IntersectMBO/ouroboros-network/blob/main/ouroboros-network-protocols/cddl/specs/local-state-query.cddl
  @message_query 3
  @message_acquire [8]
  @message_release [5]

  # See the CDDL for details on mapping of messages to numbers.
  # https://github.com/IntersectMBO/ouroboros-network/blob/main/ouroboros-network-protocols/cddl/specs/local-tx-submission.cddl
  @message_submit_tx 0

  @doc """
  Acquires a snapshot of the mempool, allowing the protocol to make queries.

  ## Examples

      iex> <<_timestamp::32, msg::binary>> = Xander.Messages.msg_acquire()
      iex> msg
      <<0, 7, 0, 2, 129, 8>>

  """
  def msg_acquire do
    payload = CBOR.encode(@message_acquire)
    header(@mini_protocols.local_state_query, payload) <> payload
  end

  @doc """
  Releases the current snapshot of the mempool, allowing the protocol to return
  to the idle state.

  ## Examples

      iex> <<_timestamp::32, msg::binary>> = Xander.Messages.msg_release()
      iex> msg
      <<0, 7, 0, 2, 129, 5>>

  """
  def msg_release do
    payload = CBOR.encode(@message_release)
    header(@mini_protocols.local_state_query, payload) <> payload
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

  @doc """
  Builds a static query to get the current epoch number.

  Payload CBOR: [3, [0, [0, [6, [1]]]]]
  Payload Bitstring: <<130, 3, 130, 0, 130, 0, 130, 6, 129, 1>>

  ## Examples

    iex> <<_timestamp::32, msg::binary>> = Xander.Messages.get_epoch_number()
    iex> msg
    <<0, 7, 0, 10, 130, 3, 130, 0, 130, 0, 130, 6, 129, 1>>
  """
  def get_epoch_number do
    payload = build_query(@get_epoch_number)
    bitstring_payload = CBOR.encode(payload)

    header(@mini_protocols.local_state_query, bitstring_payload) <> bitstring_payload
  end

  @doc """
  Builds a static query to get the current tip of the chain

  Payload CBOR: [3]
  Payload Bitstring: <<129, 3>>

  ## Examples

    iex> <<_timestamp::32, msg::binary>> = Xander.Messages.get_current_tip()
    iex> msg
    <<0, 7, 0, 4, 130, 3, 129, 3>>

  """
  @spec get_current_tip() :: binary()
  def get_current_tip do
    payload = build_query(@get_current_tip)
    bitstring_payload = CBOR.encode(payload)

    header(@mini_protocols.local_state_query, bitstring_payload) <> bitstring_payload
  end

  @spec transaction(binary()) :: binary()
  def transaction(tx_hash) do
    payload = build_transaction(tx_hash)
    bitstring_payload = CBOR.encode(payload)

    header(@mini_protocols.local_tx_submission, bitstring_payload) <> bitstring_payload
  end

  defp build_query(query), do: [@message_query, query]

  defp build_transaction(tx_hash), do: [@message_submit_tx, tx_hash]

  # middle 16 bits are: 1 bit == 0 for initiator and 15 bits for the mini protocol ID
  defp header(mini_protocol_id, payload),
    do:
      <<header_timestamp()::32>> <> <<0, mini_protocol_id>> <> <<byte_size(payload)::unsigned-16>>

  # Returns the lower 32 bits of the system's monotonic time in microseconds
  defp header_timestamp,
    do:
      System.monotonic_time(:microsecond)
      |> Bitwise.band(0xFFFFFFFF)
end

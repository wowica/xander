defmodule Xander.Util do
  @doc """
  Unwrap the multiplexer header from a CDDL message. This can be used to
  extract the payload from node responses.

  ## Examples

      iex> Xander.Util.plex(<<0, 0, 0, 0, 1, 2, 0, 3, 97, 98, 99>>)
      {:ok, %{payload: <<97, 98, 99>>, protocol_id: <<1, 2>>, size: <<0, 3>>}}

      iex> Xander.Util.plex(<<1, 2, 3>>)
      {:error, :invalid_format}

      iex> Xander.Util.plex(nil)
      {:error, :invalid_input}

  """
  @spec plex(binary() | nil) :: {:ok, map()} | {:error, atom()}
  def plex(msg) when is_binary(msg) and byte_size(msg) >= 8 do
    <<_timestamp::binary-size(4), protocol_id::binary-size(2), payload_size::binary-size(2),
      payload::binary>> = msg

    {:ok, %{payload: payload, protocol_id: protocol_id, size: payload_size}}
  end

  def plex(msg) when is_binary(msg) do
    {:error, :invalid_format}
  end

  def plex(_) do
    {:error, :invalid_input}
  end

  @doc """
  Unwrap the multiplexer header from a CDDL message and return just the result.
  Raises an error if the input is invalid.

  ## Examples

      iex> Xander.Util.plex!(<<0, 0, 0, 0, 1, 2, 0, 3, 97, 98, 99>>)
      %{payload: <<97, 98, 99>>, protocol_id: <<1, 2>>, size: <<0, 3>>}

  """
  @spec plex!(binary()) :: map()
  def plex!(msg) do
    case plex(msg) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Failed to parse multiplexed message: #{reason}"
    end
  end

  @doc """
  Add multiplexer header to a CBOR payload. This is used to format outgoing
  messages to the Cardano node.

  ## Examples

      iex> payload = <<97, 98, 99>>
      iex> result = Xander.Util.plex_encode(payload)
      iex> byte_size(result) == byte_size(payload) + 8
      true
      iex> {:ok, decoded} = Xander.Util.plex(result)
      iex> decoded.payload == payload
      true

  """
  @spec plex_encode(binary()) :: binary()
  def plex_encode(payload) when is_binary(payload) do
    timestamp = <<0, 0, 0, 0>>
    # Default protocol ID
    protocol_id = <<0, 2>>
    size = <<0, byte_size(payload)::size(8)>>

    timestamp <> protocol_id <> size <> payload
  end
end

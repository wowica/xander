defmodule Xander.Util do
  @doc """
  Unwrap the multiplexer header from a CDDL message. This can be used to
  extract the payload from node responses.

  ## Examples

      iex> Xander.Util.plex(<<0, 0, 0, 0, 0, 7, 0, 3, 97, 98, 99>>)
      {:ok, %{mode: 0, protocol_id: 7, size: 3, payload: "abc"}}

  """
  @spec plex(binary() | nil) :: {:ok, map()} | {:error, atom()}
  def plex(msg) when is_binary(msg) and byte_size(msg) >= 8 do
    <<
      _timestamp::big-32,
      mode::1,
      protocol_id::15,
      payload_size::big-16,
      payload::binary
    >> = msg

    {:ok,
     %{
       mode: mode,
       payload: payload,
       protocol_id: protocol_id,
       size: payload_size
     }}
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

      iex> Xander.Util.plex!(<<0, 0, 0, 0, 0, 7, 0, 3, 97, 98, 99>>)
      %{mode: 0, protocol_id: 7, size: 3, payload: "abc"}

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

      iex> Xander.Util.plex_encode(<<97, 98, 99>>)
      <<0, 0, 0, 0, 0, 2, 0, 3, 97, 98, 99>>
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

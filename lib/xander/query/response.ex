defmodule Xander.Query.Response do
  # See the CDDL for details on mapping of messages to numbers.
  # https://github.com/IntersectMBO/ouroboros-network/blob/main/ouroboros-network-protocols/cddl/specs/local-state-query.cddl
  @message_response 4
  @slot_timeline 1

  @type cbor :: binary()

  @doc """
  Parses the response from a query. Accepts CBOR encoded responses.

  ## Examples

      # Current tip query response (slot number and block hash)
      iex> block_bytes = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>
      iex> payload = CBOR.encode([4, [12345, %CBOR.Tag{tag: :bytes, value: block_bytes}]])
      iex> binary = Xander.Util.plex_encode(payload)
      iex> Xander.Query.Response.parse_response(binary)
      {:ok, {12345, "000102030405060708090a0b0c0d0e0f"}}

      # Current block height query response
      iex> payload = CBOR.encode([4, [1, 123456]])
      iex> binary = Xander.Util.plex_encode(payload)
      iex> Xander.Query.Response.parse_response(binary)
      {:ok, 123456}

      # Epoch number query response
      iex> payload = CBOR.encode([4, [42]])
      iex> binary = Xander.Util.plex_encode(payload)
      iex> Xander.Query.Response.parse_response(binary)
      {:ok, 42}

      # Generic response
      iex> payload = CBOR.encode([4, "some data"])
      iex> binary = Xander.Util.plex_encode(payload)
      iex> Xander.Query.Response.parse_response(binary)
      {:ok, %CBOR.Tag{tag: :bytes, value: "some data"}}

      # Error case - invalid CBOR format
      iex> payload = CBOR.encode(["not a valid response"])
      iex> binary = Xander.Util.plex_encode(payload)
      iex> Xander.Query.Response.parse_response(binary)
      {:error, :invalid_cbor}

      # Error case - invalid binary format
      iex> Xander.Query.Response.parse_response(<<0, 1, 2, 3>>)
      {:error, :invalid_format}

      # Error case - nil input
      iex> Xander.Query.Response.parse_response(nil)
      {:error, :invalid_input}
  """
  @spec parse_response(cbor()) :: {:ok, any()} | {:error, atom()}
  def parse_response(cbor_response) do
    case Xander.Util.plex(cbor_response) do
      {:ok, %{payload: cbor_response_payload}} ->
        case CBOR.decode(cbor_response_payload) do
          {:ok, decoded, ""} -> parse_cbor(decoded)
          {:error, _reason} -> {:error, :error_decoding_cbor}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # This clause parses the response from the get_current_tip query
  defp parse_cbor([@message_response, [slot_number, %CBOR.Tag{tag: :bytes, value: response}]]) do
    block_hash = Base.encode16(response, case: :lower)
    {:ok, {slot_number, block_hash}}
  end

  # This clause parses the response from the get_current_block_height query
  defp parse_cbor([@message_response, [@slot_timeline, block_height]]) do
    {:ok, block_height}
  end

  # This clause parses the response from get_epoch_number
  defp parse_cbor([@message_response, [epoch_number]]) do
    {:ok, epoch_number}
  end

  # This clause parses the response from all other queries
  defp parse_cbor([@message_response, response]) do
    {:ok, response}
  end

  defp parse_cbor(_) do
    {:error, :invalid_cbor}
  end
end

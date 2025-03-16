defmodule Xander.Handshake.Response do
  @moduledoc """
  This module is responsible for validating and parsing the
  handshake response from a Cardano node.
  """

  defstruct [:type, :version_number, :network_magic, :query]

  alias Xander.Util

  @supported_versions [32783, 32784, 32785]
  @msg_accept_version 1
  @msg_refuse 2
  @msg_query_reply 3

  @doc """
  Validates the handshake response from a Cardano node.

  ## Examples

      # Valid msgAcceptVersion response
      iex> payload = CBOR.encode([1, 32784, [764824073, %{"versions" => [1, 2, 3]}]])
      iex> response = Xander.Util.plex_encode(payload)
      iex> {:ok, result} = Xander.Handshake.Response.validate(response)
      iex> result.type == :msg_accept_version and result.version_number == 32784
      true

      # Unsupported version in msgAcceptVersion
      iex> payload = CBOR.encode([1, 12345, [764824073, %{"versions" => [1, 2, 3]}]])
      iex> response = Xander.Util.plex_encode(payload)
      iex> Xander.Handshake.Response.validate(response)
      {:error, "Only versions [32783, 32784, 32785] are supported."}

      # Version mismatch refuse response
      iex> payload = CBOR.encode([2, [0, <<1, 2, 3, 4>>]])
      iex> response = Xander.Util.plex_encode(payload)
      iex> {:refused, result} = Xander.Handshake.Response.validate(response)
      iex> result.type
      :version_mismatch

      # Handshake decode error refuse response
      iex> payload = CBOR.encode([2, [1, 32784, "decode error"]])
      iex> response = Xander.Util.plex_encode(payload)
      iex> {:refused, result} = Xander.Handshake.Response.validate(response)
      iex> result.type
      :handshake_decode_error

      # Refused version refuse response
      iex> payload = CBOR.encode([2, [2, 32784, "refused"]])
      iex> response = Xander.Util.plex_encode(payload)
      iex> {:refused, result} = Xander.Handshake.Response.validate(response)
      iex> result.type
      :refused

      # Unknown refuse reason
      iex> payload = CBOR.encode([2, [99, "unknown"]])
      iex> response = Xander.Util.plex_encode(payload)
      iex> {:refused, result} = Xander.Handshake.Response.validate(response)
      iex> result.type
      :unknown_refuse_reason

      # Query reply response
      iex> payload = CBOR.encode([3, %{"supported" => [32783, 32784, 32785]}])
      iex> response = Xander.Util.plex_encode(payload)
      iex> Xander.Handshake.Response.validate(response)
      {:versions, %{%CBOR.Tag{tag: :bytes, value: "supported"} => [32783, 32784, 32785]}}

      # Unknown message type
      iex> payload = CBOR.encode([99, "unknown"])
      iex> response = Xander.Util.plex_encode(payload)
      iex> Xander.Handshake.Response.validate(response)
      {:error, "Unknown message format"}

      # Error in CBOR decoding
      iex> response = <<0, 1, 2, 3>> # Invalid CBOR
      iex> Xander.Handshake.Response.validate(response)
      {:error, :invalid_format}
  """
  def validate(response) do
    with {:ok, %{payload: payload}} <- Util.plex(response),
         {:ok, decoded} <- decode_cbor(payload) do
      process_decoded_message(decoded)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_cbor(payload) do
    case CBOR.decode(payload) do
      {:ok, decoded, ""} -> {:ok, decoded}
      {:error, reason} -> {:error, reason}
    end
  end

  # Handle msgAcceptVersion (1)
  defp process_decoded_message([@msg_accept_version, version, [magic, query]]) do
    if version in @supported_versions do
      {:ok,
       %__MODULE__{
         network_magic: magic,
         query: query,
         type: :msg_accept_version,
         version_number: version
       }}
    else
      {:error, "Only versions #{inspect(@supported_versions)} are supported."}
    end
  end

  # Handle msgRefuse (2)
  defp process_decoded_message([@msg_refuse, refuse_reason]) do
    process_refuse_reason(refuse_reason)
  end

  # Handle msgQueryReply (3)
  defp process_decoded_message([@msg_query_reply, version_table]) do
    # TODO: parse version_table
    {:versions, version_table}
  end

  defp process_decoded_message(_) do
    {:error, "Unknown message format"}
  end

  defp process_refuse_reason([0, _version_number_binary]) do
    # TODO: return accepted versions; reduce to 32783-32785
    {:refused, %__MODULE__{type: :version_mismatch}}
  end

  defp process_refuse_reason([1, _any_version_number, _tstr]) do
    {:refused, %__MODULE__{type: :handshake_decode_error}}
  end

  defp process_refuse_reason([2, _any_version_number, _tstr]) do
    {:refused, %__MODULE__{type: :refused}}
  end

  defp process_refuse_reason(_) do
    {:refused, %__MODULE__{type: :unknown_refuse_reason}}
  end
end

defmodule Xander.Transaction.Response do
  @moduledoc """
  Parses the response from a transaction. Accepts CBOR encoded responses.
  """

  require Logger

  @doc """
  Parses the response from a transaction. Accepts CBOR encoded responses.

  ## Examples

      # Transaction accepted
      iex> binary = Xander.Util.plex_encode(CBOR.encode([1]))
      iex> Xander.Transaction.Response.parse_response(binary)
      {:ok, :accepted}

      # Transaction rejected with reason
      iex> tag = %CBOR.Tag{tag: :bytes, value: "invalid tx"}
      iex> binary = Xander.Util.plex_encode(CBOR.encode([2, tag]))
      iex> Xander.Transaction.Response.parse_response(binary)
      {:error, {:rejected, %CBOR.Tag{tag: :bytes, value: "invalid tx"}}}

      # Disconnected from node
      iex> binary = Xander.Util.plex_encode(CBOR.encode([3]))
      iex> Xander.Transaction.Response.parse_response(binary)
      {:error, :disconnected}

      # Error handling invalid CBOR
      iex> Xander.Transaction.Response.parse_response(<<0, 1, 2, 3>>)
      {:error, :invalid_format}

      # Error handling nil input
      iex> Xander.Transaction.Response.parse_response(nil)
      {:error, :invalid_input}
  """
  @spec parse_response(binary() | nil) ::
          {:error,
           :cannot_decode_non_binary_values
           | :cbor_function_clause_error
           | :cbor_match_error
           | :invalid_format
           | :invalid_input
           | :disconnected
           | {:rejected, any()}}
          | {:ok, :accepted}
  def parse_response(cbor_response) do
    case Xander.Util.plex(cbor_response) do
      {:ok, %{payload: cbor_response_payload}} ->
        decode(cbor_response_payload)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode(cbor_response_payload) do
    case CBOR.decode(cbor_response_payload) do
      {:ok, [1], <<>>} ->
        {:ok, :accepted}

      {:ok, [2, failure_reason], <<>>} ->
        {:error, {:rejected, failure_reason}}

      {:ok, [3], <<>>} ->
        {:error, :disconnected}

      {:error, error} ->
        {:error, error}
    end
  end
end

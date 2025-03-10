defmodule Xander.Handshake.Response do
  @moduledoc """
  This module is responsible for validating and parsing the
  handshake response from a Cardano node.
  """

  defstruct [:type, :version_number, :network_magic, :query]

  alias Xander.Util

  @doc """
  Validates the handshake response from a Cardano node.
  """
  def validate(response) do
    %{payload: payload} = Util.plex(response)

    case CBOR.decode(payload) do
      # msgAcceptVersion
      {:ok, [1, version, [magic, query]], ""} ->
        if version in [32783, 32784, 32785] do
          {:ok,
           %__MODULE__{
             network_magic: magic,
             query: query,
             type: :msg_accept_version,
             version_number: version
           }}
        else
          {:error, "Only versions 32783, 32784, and 32785 are supported."}
        end

      # msgRefuse
      {:ok, [2, refuse_reason], ""} ->
        case refuse_reason do
          # TODO: return accepted versions; reduce to 32783 and 32784
          [0, _version_number_binary] ->
            {:refused, %__MODULE__{type: :version_mismatch}}

          [1, _anyVersionNumber, _tstr] ->
            {:refused, %__MODULE__{type: :handshake_decode_error}}

          [2, _anyVersionNumber, _tstr] ->
            {:refused, %__MODULE__{type: :refused}}
        end

      # TODO: parse version_table
      # msgQueryReply
      {:ok, [3, version_table], ""} ->
        {:versions, version_table}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

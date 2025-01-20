defmodule Xander.HandshakeResponse do
  defstruct [:type, :version_number, :network_magic, :query]

  def parse_response(full_response) do
    # Only works when connecting via Unix socket
    <<_header_todo_investigate::binary-size(8), response_payload::binary>> = full_response

    case CBOR.decode(response_payload) do
      {:ok, decoded, ""} ->
        parse_cbor(decoded)

      {:error, _reason} ->
        {:error, :error_decoding_cbor}
    end
  end

  defp parse_cbor([1, version_number, [network_magic, query] = node_to_client_version_data]) do
    with true <- is_valid_version_number(version_number),
         true <- is_valid_version_data(node_to_client_version_data) do
      {
        :ok,
        %__MODULE__{
          type: :msg_accept_version,
          version_number: version_number,
          network_magic: network_magic,
          query: query
        }
      }
    else
      _ ->
        {:error, :invalid_data}
    end
  end

  defp parse_cbor(_), do: {:error, :unsupported_message_type}

  # Validates version number according to CDDL definition (32783 or 32784)
  @version_numbers [32783, 32784]
  defp is_valid_version_number(version_number) do
    version_number in @version_numbers
  end

  # Check if the node to client version data matches expected format
  defp is_valid_version_data([network_magic, query]) do
    is_integer(network_magic) and is_boolean(query)
  end

  defp is_valid_version_data(_), do: false
end

defmodule Xander.LocalStateQueryResponse do
  def parse_response(full_response) do
    <<_header_todo_investigate::binary-size(8), response_payload::binary>> = full_response

    case CBOR.decode(response_payload) do
      {:ok, decoded, ""} -> parse_cbor(decoded)
      {:error, _reason} -> {:error, :error_decoding_cbor}
    end
  end

  defp parse_cbor([4, response]) do
    {:ok, response}
  end

  defp parse_cbor(_) do
    {:error, :invalid_cbor}
  end
end

defmodule Xander.Query.Response do
  # See the CDDL for details on mapping of messages to numbers.
  # https://github.com/IntersectMBO/ouroboros-network/blob/main/ouroboros-network-protocols/cddl/specs/local-state-query.cddl
  @message_response 4
  @slot_timeline 1

  def parse_response(full_response) do
    %{payload: response_payload} = Xander.Util.plex(full_response)

    case CBOR.decode(response_payload) do
      {:ok, decoded, ""} -> parse_cbor(decoded)
      {:error, _reason} -> {:error, :error_decoding_cbor}
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

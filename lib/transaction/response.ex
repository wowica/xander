defmodule Xander.Transaction.Response do
  def parse_response(cbor_response) do
    %{payload: cbor_response_payload, protocol_id: _protocol_id, size: _size} =
      Xander.Util.plex(cbor_response)

    cbor_response_payload
  end
end

defmodule Xander.ChainSync.Response do
  def parse_response(response) do
    %{payload: response_payload} = Xander.Util.plex(response)

    CBOR.decode(response_payload)
  end
end

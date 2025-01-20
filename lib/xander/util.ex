defmodule Xander.Util do
  @doc """
  Unwrap the multiplexer header from the CDDL message.
  """
  @spec plex(binary) :: map()
  def plex(msg) do
    <<_ts::binary-size(4), protocol_id::binary-size(2), payload_size::binary-size(2),
      payload::binary>> = msg

    %{payload: payload, protocol_id: protocol_id, size: payload_size}
  end
end

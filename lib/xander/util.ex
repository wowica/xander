defmodule Xander.Util do
  @doc """
  Unwrap the multiplexer header from a CDDL message. This can be used to
  extract the payload from node responses.

  ## Examples

      iex> Xander.Util.plex(<<0, 0, 0, 0, 1, 2, 0, 3, 97, 98, 99>>)
      %{payload: <<97, 98, 99>>, protocol_id: <<1, 2>>, size: <<0, 3>>}

  """
  @spec plex(binary) :: map()
  def plex(msg) do
    <<_timestamp::binary-size(4), protocol_id::binary-size(2), payload_size::binary-size(2),
      payload::binary>> = msg

    %{payload: payload, protocol_id: protocol_id, size: payload_size}
  end
end

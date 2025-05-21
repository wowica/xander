defmodule Xander.ChainSync.Response do
  alias Xander.Util

  def parse_response(response) do
    case Util.plex(response) do
      {:ok, %{payload: response_payload}} ->
        {:ok, response_payload}

      _ ->
        {:error, "Failed to parse response"}
    end
  end
end

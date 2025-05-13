defmodule Xander.ChainSync.Response do
  alias Xander.Util

  def parse_response(response) do
    with {:ok, %{payload: response_payload}} <- Util.plex(response) do
      case CBOR.decode(response_payload) do
        {:ok, response, ""} ->
          {:ok, response}

        {:error, _} ->
          {:error, "Failed to parse response"}
      end
    else
      {:error, _} ->
        {:error, "Failed to parse response"}
    end
  end
end

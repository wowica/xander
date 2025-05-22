defmodule Xander.ChainSync.Intersection do
  alias Xander.Messages
  alias Xander.ChainSync.Response
  alias Xander.ChainSync.Response.RollBackward
  alias Xander.ChainSync.Response.IntersectFound
  alias Xander.ChainSync.Ledger

  require Logger

  @recv_timeout 10_000

  def find_target(client, socket, sync_from) do
    with :ok <- client.send(socket, Messages.next_request()),
         {:ok, intersection_response} <- client.recv(socket, 0, @recv_timeout),
         {:ok, %RollBackward{tip: tip}} <- Response.parse_response(intersection_response) do
      case sync_from do
        :conway ->
          {:ok, Ledger.conway_boundary_target()}

        {slot_number, block_hash} ->
          {:ok, Ledger.custom_point_target(slot_number, block_hash)}

        _ ->
          {:ok, Ledger.custom_point_target(tip.slot_number, tip.hash)}
      end
    else
      {:error, reason} ->
        Logger.error("Error finding initial intersection: #{inspect(reason)}")
        {:error, :error_finding_initial_intersection}
    end
  end

  def find_intersection(client, socket, tslot, tbytes) do
    message = Messages.find_intersection(tslot, tbytes)
    :ok = client.send(socket, message)

    case client.recv(socket, 0, @recv_timeout) do
      {:ok, intersection_response} ->
        Logger.debug("Find intersection response successful")

        case Response.parse_response(intersection_response) do
          {:ok,
           %IntersectFound{
             point: %{slot_number: ^tslot, bytes: ^tbytes}
           } = intersect} ->
            {:ok, intersect}

          {:error, _error} ->
            {:error, :intersection_not_found}
        end

      {:error, reason} ->
        Logger.warning("Find intersection response failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

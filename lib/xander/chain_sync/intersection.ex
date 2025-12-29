defmodule Xander.ChainSync.Intersection do
  alias Xander.Messages
  alias Xander.ChainSync.Response
  alias Xander.Transport
  alias Xander.ChainSync.Response.RollBackward
  alias Xander.ChainSync.Response.IntersectFound
  alias Xander.ChainSync.Ledger

  require Logger

  @recv_timeout 10_000

  def find_target(transport, socket, sync_from) do
    with :ok <- Transport.send(transport, socket, Messages.next_request()),
         {:ok, intersection_response} <- Transport.recv(transport, socket, 0, @recv_timeout),
         {:ok, %RollBackward{tip: tip}} <- Response.parse_response(intersection_response) do
      case sync_from do
        :conway ->
          {:ok, Ledger.conway_boundary_target()}

        :origin ->
          {:ok, Ledger.genesis_target()}

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

  def find_intersection(transport, socket, tslot, tbytes) do
    message = Messages.find_intersection(tslot, tbytes)
    :ok = Transport.send(transport, socket, message)

    case Transport.recv(transport, socket, 0, @recv_timeout) do
      {:ok, intersection_response} ->
        Logger.debug("Find intersection response successful")

        case Response.parse_response(intersection_response) do
          {:ok,
           %IntersectFound{
             point: %{slot_number: ^tslot, bytes: ^tbytes, hash: hash}
           } = intersect} ->
            Logger.debug("Syncing from slot: #{tslot}, block hash: #{hash}")

            {:ok, intersect}

          {:ok, %IntersectFound{} = intersect} ->
            Logger.debug("Syncing from origin")
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

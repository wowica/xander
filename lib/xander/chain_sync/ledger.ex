defmodule Xander.ChainSync.Ledger do
  @moduledoc """
  Provides functionality for chain synchronization intersection points.
  """

  # TODO: Consider re-using Xander.ChainSync.Response.Block since it's the same shape as IntersectionTarget.
  # Leaving it here for now for semantics.
  defmodule IntersectionTarget do
    @moduledoc """
    Represents a chain intersection point with slot number, block hash, and block bytes.
    """
    defstruct [:slot, :block_hash, :block_bytes]

    @type t :: %__MODULE__{
            slot: non_neg_integer(),
            block_hash: String.t(),
            block_bytes: binary()
          }
  end

  def conway_boundary_target do
    # Last babbage block
    slot = 133_660_799
    block_hash = "e757d57eb8dc9500a61c60a39fadb63d9be6973ba96ae337fd24453d4d15c343"
    block_bytes = Base.decode16!(block_hash, case: :lower)

    %IntersectionTarget{slot: slot, block_hash: block_hash, block_bytes: block_bytes}
  end

  # Last block of the Alonzo era on each network. Intersecting at this point
  # makes the node stream blocks starting from the first Babbage block.
  @babbage_boundaries %{
    # First Babbage block on preview is block 13012 at slot 259215.
    preview: {259_180, "0ad91d3bbe350b1cfa05b13dba5263c47c5eca4f97b3a3105eba96416785a487"}
  }

  @doc """
  Returns the networks for which a Babbage era boundary point is known.
  """
  def babbage_supported_networks, do: Map.keys(@babbage_boundaries)

  @doc """
  Returns the last Alonzo era block of the given network as an intersection
  target, so that syncing starts from the first Babbage block.
  """
  def babbage_boundary_target(network) do
    case Map.fetch(@babbage_boundaries, network) do
      {:ok, {slot, block_hash}} -> {:ok, custom_point_target(slot, block_hash)}
      :error -> {:error, {:unsupported_network, network}}
    end
  end

  def custom_point_target(slot_number, block_hash) do
    block_bytes = Base.decode16!(block_hash, case: :lower)

    %IntersectionTarget{slot: slot_number, block_hash: block_hash, block_bytes: block_bytes}
  end

  def genesis_target do
    %IntersectionTarget{slot: nil, block_hash: nil, block_bytes: nil}
  end
end

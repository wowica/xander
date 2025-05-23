defmodule Xander.ChainSync.Ledger do
  @moduledoc """
  Provides functionality for chain synchronization intersection points.
  """

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

  def custom_point_target(slot_number, block_hash) do
    block_bytes = Base.decode16!(block_hash, case: :lower)

    %IntersectionTarget{slot: slot_number, block_hash: block_hash, block_bytes: block_bytes}
  end
end

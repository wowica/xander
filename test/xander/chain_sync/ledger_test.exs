defmodule Xander.ChainSync.LedgerTest do
  use ExUnit.Case, async: true

  alias Xander.ChainSync.Ledger
  alias Xander.ChainSync.Ledger.IntersectionTarget

  describe "conway_boundary_target/0" do
    test "returns the last babbage block as intersection target" do
      target = Ledger.conway_boundary_target()

      assert %IntersectionTarget{} = target
      assert target.slot == 133_660_799

      assert target.block_hash ==
               "e757d57eb8dc9500a61c60a39fadb63d9be6973ba96ae337fd24453d4d15c343"
    end

    test "block_bytes is the decoded hex of block_hash" do
      target = Ledger.conway_boundary_target()

      expected_bytes = Base.decode16!(target.block_hash, case: :lower)
      assert target.block_bytes == expected_bytes
    end

    test "block_bytes is 32 bytes (256 bits)" do
      target = Ledger.conway_boundary_target()

      assert byte_size(target.block_bytes) == 32
    end
  end

  describe "custom_point_target/2" do
    test "creates intersection target with given slot and hash" do
      slot = 100_000
      hash = "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"

      target = Ledger.custom_point_target(slot, hash)

      assert %IntersectionTarget{} = target
      assert target.slot == slot
      assert target.block_hash == hash
    end

    test "decodes block_hash to block_bytes" do
      slot = 50_000
      hash = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

      target = Ledger.custom_point_target(slot, hash)

      expected_bytes = Base.decode16!(hash, case: :lower)
      assert target.block_bytes == expected_bytes
    end

    test "requires lowercase hex hash" do
      slot = 75_000
      uppercase_hash = "ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890"

      # Function uses case: :lower, so uppercase will raise
      assert_raise ArgumentError, fn ->
        Ledger.custom_point_target(slot, uppercase_hash)
      end
    end
  end

  describe "genesis_target/0" do
    test "returns intersection target with all nil values" do
      target = Ledger.genesis_target()

      assert %IntersectionTarget{} = target
      assert target.slot == nil
      assert target.block_hash == nil
      assert target.block_bytes == nil
    end

    test "represents the origin/genesis point" do
      target = Ledger.genesis_target()

      assert target == %IntersectionTarget{slot: nil, block_hash: nil, block_bytes: nil}
    end
  end
end

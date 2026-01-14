defmodule Xander.ChainSync.IntersectionTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Xander.ChainSync.Intersection
  alias Xander.ChainSync.Ledger
  alias Xander.ChainSync.Ledger.IntersectionTarget
  alias Xander.Transport

  defmodule FakeClient do
    def send(_socket, _data), do: :ok

    def recv(socket, _length, _timeout) do
      case socket do
        {:test_response, response} -> {:ok, response}
        {:test_error, reason} -> {:error, reason}
      end
    end
  end

  defp test_transport do
    %Transport{
      type: :socket,
      client: FakeClient,
      setopts_module: :inet,
      path: {:local, "/tmp/test.socket"},
      port: 0,
      connect_opts: []
    }
  end

  defp build_roll_backward_response(tip_slot, tip_block_bytes) do
    # Empty point represents origin
    point = []

    # Build tip block
    tip = [
      [tip_slot, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
      100
    ]

    cbor_payload = CBOR.encode([3, point, tip])

    # Wrap in multiplexer format: timestamp (4 bytes) + mode/protocol (2 bytes) + size (2 bytes) + payload
    timestamp = <<0, 0, 0, 0>>
    mode_and_protocol = <<0, 2>>
    size = <<byte_size(cbor_payload)::big-16>>
    timestamp <> mode_and_protocol <> size <> cbor_payload
  end

  defp build_intersect_found_response(point_slot, point_block_bytes, tip_slot, tip_block_bytes) do
    point = [
      point_slot,
      %CBOR.Tag{tag: :bytes, value: point_block_bytes}
    ]

    tip = [
      [tip_slot, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
      200
    ]

    cbor_payload = CBOR.encode([5, point, tip])

    timestamp = <<0, 0, 0, 0>>
    mode_and_protocol = <<0, 2>>
    size = <<byte_size(cbor_payload)::big-16>>
    timestamp <> mode_and_protocol <> size <> cbor_payload
  end

  defp build_origin_intersect_found_response(tip_slot, tip_block_bytes) do
    # Empty point represents origin
    point = []

    tip = [
      [tip_slot, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
      200
    ]

    cbor_payload = CBOR.encode([5, point, tip])

    timestamp = <<0, 0, 0, 0>>
    mode_and_protocol = <<0, 2>>
    size = <<byte_size(cbor_payload)::big-16>>
    timestamp <> mode_and_protocol <> size <> cbor_payload
  end

  defp build_invalid_response do
    cbor_payload = CBOR.encode([99, "invalid", "data"])

    timestamp = <<0, 0, 0, 0>>
    mode_and_protocol = <<0, 2>>
    size = <<byte_size(cbor_payload)::big-16>>
    timestamp <> mode_and_protocol <> size <> cbor_payload
  end

  describe "find_target/3" do
    test "returns conway boundary target when sync_from is :conway" do
      tip_slot = 150_000_000
      tip_block_bytes = :crypto.strong_rand_bytes(32)
      response = build_roll_backward_response(tip_slot, tip_block_bytes)

      transport = test_transport()
      socket = {:test_response, response}

      assert {:ok, target} = Intersection.find_target(transport, socket, :conway)
      assert target == Ledger.conway_boundary_target()
      assert %IntersectionTarget{slot: 133_660_799} = target
    end

    test "returns genesis target when sync_from is :origin" do
      tip_slot = 150_000_000
      tip_block_bytes = :crypto.strong_rand_bytes(32)
      response = build_roll_backward_response(tip_slot, tip_block_bytes)

      transport = test_transport()
      socket = {:test_response, response}

      assert {:ok, target} = Intersection.find_target(transport, socket, :origin)
      assert target == Ledger.genesis_target()
      assert %IntersectionTarget{slot: nil, block_hash: nil, block_bytes: nil} = target
    end

    test "returns custom point target when sync_from is a tuple {slot, hash}" do
      tip_slot = 150_000_000
      tip_block_bytes = :crypto.strong_rand_bytes(32)
      response = build_roll_backward_response(tip_slot, tip_block_bytes)

      custom_slot = 100_000
      custom_hash = "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"

      transport = test_transport()
      socket = {:test_response, response}

      assert {:ok, target} =
               Intersection.find_target(transport, socket, {custom_slot, custom_hash})

      assert target == Ledger.custom_point_target(custom_slot, custom_hash)
      assert %IntersectionTarget{slot: ^custom_slot, block_hash: ^custom_hash} = target
    end

    test "returns target from tip when sync_from is any other value" do
      tip_slot = 150_000_000
      tip_block_bytes = :crypto.strong_rand_bytes(32)
      tip_hash = Base.encode16(tip_block_bytes, case: :lower)
      response = build_roll_backward_response(tip_slot, tip_block_bytes)

      transport = test_transport()
      socket = {:test_response, response}

      # Using :latest as an example of "any other value"
      assert {:ok, target} = Intersection.find_target(transport, socket, :latest)

      assert %IntersectionTarget{slot: ^tip_slot, block_hash: ^tip_hash} = target
    end

    test "returns target from tip when sync_from is nil" do
      tip_slot = 200_000_000
      tip_block_bytes = :crypto.strong_rand_bytes(32)
      tip_hash = Base.encode16(tip_block_bytes, case: :lower)
      response = build_roll_backward_response(tip_slot, tip_block_bytes)

      transport = test_transport()
      socket = {:test_response, response}

      assert {:ok, target} = Intersection.find_target(transport, socket, nil)

      assert %IntersectionTarget{slot: ^tip_slot, block_hash: ^tip_hash} = target
    end

    test "returns error when transport recv fails" do
      transport = test_transport()
      socket = {:test_error, :timeout}

      log =
        capture_log(fn ->
          assert {:error, :error_finding_initial_intersection} =
                   Intersection.find_target(transport, socket, :conway)
        end)

      assert log =~ "Error finding initial intersection"
      assert log =~ "timeout"
    end

    test "returns error when response parsing fails" do
      response = build_invalid_response()

      transport = test_transport()
      socket = {:test_response, response}

      log =
        capture_log(fn ->
          assert {:error, :error_finding_initial_intersection} =
                   Intersection.find_target(transport, socket, :conway)
        end)

      assert log =~ "Error finding initial intersection"
    end
  end

  describe "find_intersection/4" do
    test "returns IntersectFound when intersection matches requested slot and bytes" do
      target_slot = 133_660_799

      target_block_bytes =
        Base.decode16!("e757d57eb8dc9500a61c60a39fadb63d9be6973ba96ae337fd24453d4d15c343",
          case: :lower
        )

      tip_slot = 150_000_000
      tip_block_bytes = :crypto.strong_rand_bytes(32)

      response =
        build_intersect_found_response(target_slot, target_block_bytes, tip_slot, tip_block_bytes)

      transport = test_transport()
      socket = {:test_response, response}

      assert {:ok, intersect} =
               Intersection.find_intersection(transport, socket, target_slot, target_block_bytes)

      assert intersect.point.slot_number == target_slot
      assert intersect.point.bytes == target_block_bytes
      assert intersect.tip.slot_number == tip_slot
    end

    test "returns IntersectFound when syncing from origin (empty point)" do
      tip_slot = 150_000_000
      tip_block_bytes = :crypto.strong_rand_bytes(32)

      response = build_origin_intersect_found_response(tip_slot, tip_block_bytes)

      transport = test_transport()
      socket = {:test_response, response}

      # When syncing from origin, slot is nil and bytes is nil
      assert {:ok, intersect} =
               Intersection.find_intersection(transport, socket, nil, nil)

      assert intersect.tip.slot_number == tip_slot
    end

    test "returns error when intersection is not found" do
      response = build_invalid_response()

      transport = test_transport()
      socket = {:test_response, response}

      target_slot = 100_000
      target_bytes = :crypto.strong_rand_bytes(32)

      assert {:error, :intersection_not_found} =
               Intersection.find_intersection(transport, socket, target_slot, target_bytes)
    end

    test "returns error when transport recv fails" do
      transport = test_transport()
      socket = {:test_error, :closed}

      target_slot = 100_000
      target_bytes = :crypto.strong_rand_bytes(32)

      log =
        capture_log(fn ->
          assert {:error, :closed} =
                   Intersection.find_intersection(transport, socket, target_slot, target_bytes)
        end)

      assert log =~ "Find intersection response failed"
      assert log =~ "closed"
    end

    test "returns error when transport times out" do
      transport = test_transport()
      socket = {:test_error, :timeout}

      target_slot = 100_000
      target_bytes = :crypto.strong_rand_bytes(32)

      log =
        capture_log(fn ->
          assert {:error, :timeout} =
                   Intersection.find_intersection(transport, socket, target_slot, target_bytes)
        end)

      assert log =~ "Find intersection response failed"
    end

    test "returns intersection when point slot matches but different origin format" do
      # Test the case where IntersectFound matches but not the specific pattern match
      # This tests the second clause: {:ok, %IntersectFound{} = intersect}
      tip_slot = 150_000_000
      tip_block_bytes = :crypto.strong_rand_bytes(32)

      # Build response with different slot/bytes than requested
      response_slot = 99_999
      response_bytes = :crypto.strong_rand_bytes(32)

      response =
        build_intersect_found_response(response_slot, response_bytes, tip_slot, tip_block_bytes)

      transport = test_transport()
      socket = {:test_response, response}

      # Request with different slot/bytes - should still return the intersect found
      # because it matches the IntersectFound pattern but not the specific slot/bytes
      requested_slot = 100_000
      requested_bytes = :crypto.strong_rand_bytes(32)

      assert {:ok, intersect} =
               Intersection.find_intersection(transport, socket, requested_slot, requested_bytes)

      # The response point should be what was in the response, not what was requested
      assert intersect.point.slot_number == response_slot
    end
  end
end

defmodule Xander.ChainSync.ResponseTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Xander.ChainSync.Response

  alias Xander.ChainSync.Response.{
    AwaitReply,
    Block,
    Header,
    IntersectFound,
    RollBackward,
    RollForward
  }

  @encoded_cbor_data_tag 24

  describe "decode/1" do
    test "decodes AwaitReply response" do
      cbor_data = CBOR.encode([1])

      assert {:ok, %AwaitReply{}} = Response.decode(cbor_data)
    end

    test "decodes RollForward response with header and tip" do
      # Conway era header
      block_number = 12345
      block_body_size = 6789

      header_content = [
        0,
        [[[block_number, 1, 2, 3, 4, 5, block_body_size, 7, 8], []], []]
      ]

      header_bytes = CBOR.encode(header_content)

      header = %CBOR.Tag{
        tag: @encoded_cbor_data_tag,
        value: %CBOR.Tag{
          tag: :bytes,
          value: header_bytes
        }
      }

      # Build tip block
      slot_number = 54321
      block_bytes = :crypto.strong_rand_bytes(32)

      tip = [
        [slot_number, %CBOR.Tag{tag: :bytes, value: block_bytes}],
        100
      ]

      cbor_data = CBOR.encode([2, header, tip])

      assert {:ok, %RollForward{header: parsed_header, tip: parsed_tip}} =
               Response.decode(cbor_data)

      assert %Header{
               block_number: ^block_number,
               block_body_size: ^block_body_size,
               bytes: ^header_bytes
             } = parsed_header

      assert %Block{
               slot_number: ^slot_number,
               bytes: ^block_bytes
             } = parsed_tip

      assert parsed_tip.hash == Base.encode16(block_bytes, case: :lower)
    end

    test "decodes RollBackward response with point and tip" do
      # Build point
      point_slot_number = 11111
      point_block_bytes = :crypto.strong_rand_bytes(32)

      point = [
        point_slot_number,
        %CBOR.Tag{tag: :bytes, value: point_block_bytes}
      ]

      # Build tip block
      tip_slot_number = 22222
      tip_block_bytes = :crypto.strong_rand_bytes(32)

      tip = [
        [tip_slot_number, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
        200
      ]

      cbor_data = CBOR.encode([3, point, tip])

      assert {:ok, %RollBackward{point: parsed_point, tip: parsed_tip}} =
               Response.decode(cbor_data)

      assert %Block{
               slot_number: ^point_slot_number,
               bytes: ^point_block_bytes
             } = parsed_point

      assert parsed_point.hash == Base.encode16(point_block_bytes, case: :lower)

      assert %Block{
               slot_number: ^tip_slot_number,
               bytes: ^tip_block_bytes
             } = parsed_tip
    end

    test "decodes RollBackward with empty point (origin)" do
      # Empty point represents origin
      point = []

      # Build tip block
      tip_slot_number = 33333
      tip_block_bytes = :crypto.strong_rand_bytes(32)

      tip = [
        [tip_slot_number, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
        300
      ]

      cbor_data = CBOR.encode([3, point, tip])

      assert {:ok, %RollBackward{point: parsed_point, tip: parsed_tip}} =
               Response.decode(cbor_data)

      # Empty point returns empty map
      assert parsed_point == %{}

      assert %Block{slot_number: ^tip_slot_number} = parsed_tip
    end

    test "decodes IntersectFound response" do
      # Build point
      point_slot_number = 44444
      point_block_bytes = :crypto.strong_rand_bytes(32)

      point = [
        point_slot_number,
        %CBOR.Tag{tag: :bytes, value: point_block_bytes}
      ]

      # Build tip block
      tip_slot_number = 55555
      tip_block_bytes = :crypto.strong_rand_bytes(32)

      tip = [
        [tip_slot_number, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
        400
      ]

      cbor_data = CBOR.encode([5, point, tip])

      assert {:ok, %IntersectFound{point: parsed_point, tip: parsed_tip}} =
               Response.decode(cbor_data)

      assert %Block{
               slot_number: ^point_slot_number,
               bytes: ^point_block_bytes
             } = parsed_point

      assert %Block{
               slot_number: ^tip_slot_number,
               bytes: ^tip_block_bytes
             } = parsed_tip
    end

    test "returns error for unknown response type" do
      cbor_data = CBOR.encode([99, "some", "data"])

      assert {:error, :unknown_response} = Response.decode(cbor_data)
    end

    test "returns error for incomplete CBOR data" do
      # Incomplete array (says 3 items but only has 2)
      incomplete_cbor = <<0x83, 0x01, 0x02>>

      assert {:error, :incomplete_cbor_data} = Response.decode(incomplete_cbor)
    end
  end

  describe "parse_response/1" do
    test "parses a valid multiplexed response" do
      # Create the CBOR payload (AwaitReply)
      cbor_payload = CBOR.encode([1])

      # Wrap in multiplexer format: timestamp (4 bytes) + mode/protocol (2 bytes) + size (2 bytes) + payload
      timestamp = <<0, 0, 0, 0>>
      mode_and_protocol = <<0, 2>>
      size = <<byte_size(cbor_payload)::big-16>>
      multiplexed_response = timestamp <> mode_and_protocol <> size <> cbor_payload

      assert {:ok, %AwaitReply{}} = Response.parse_response(multiplexed_response)
    end

    test "parses a multiplexed RollForward response" do
      block_number = 99999
      block_body_size = 88888

      header_content = [
        0,
        [[[block_number, 1, 2, 3, 4, 5, block_body_size, 7, 8], []], []]
      ]

      header_bytes = CBOR.encode(header_content)

      header = %CBOR.Tag{
        tag: @encoded_cbor_data_tag,
        value: %CBOR.Tag{
          tag: :bytes,
          value: header_bytes
        }
      }

      # Build tip
      slot_number = 77777
      block_bytes = :crypto.strong_rand_bytes(32)

      tip = [
        [slot_number, %CBOR.Tag{tag: :bytes, value: block_bytes}],
        500
      ]

      cbor_payload = CBOR.encode([2, header, tip])

      # Wrap in multiplexer format
      timestamp = <<0, 0, 0, 0>>
      mode_and_protocol = <<0, 2>>
      size = <<byte_size(cbor_payload)::big-16>>
      multiplexed_response = timestamp <> mode_and_protocol <> size <> cbor_payload

      assert {:ok, %RollForward{header: parsed_header, tip: parsed_tip}} =
               Response.parse_response(multiplexed_response)

      assert parsed_header.block_number == block_number
      assert parsed_header.block_body_size == block_body_size
      assert parsed_tip.slot_number == slot_number
    end

    test "returns error for invalid multiplexed format" do
      # Message too short (< 8 bytes)
      short_message = <<0, 0, 0, 0, 0>>

      assert {:error, "Failed to parse response"} = Response.parse_response(short_message)
    end

    test "returns error for nil input" do
      assert {:error, "Failed to parse response"} = Response.parse_response(nil)
    end
  end

  describe "parse_header error handling" do
    test "returns error and logs message for unsupported era header format" do
      # Create a header that doesn't match the conway era pattern
      unsupported_header_content = [1, 2, 3]
      header_bytes = CBOR.encode(unsupported_header_content)

      header = %CBOR.Tag{
        tag: @encoded_cbor_data_tag,
        value: %CBOR.Tag{
          tag: :bytes,
          value: header_bytes
        }
      }

      # Build tip
      block_bytes = :crypto.strong_rand_bytes(32)

      tip = [
        [12345, %CBOR.Tag{tag: :bytes, value: block_bytes}],
        100
      ]

      cbor_data = CBOR.encode([2, header, tip])

      log =
        capture_log(fn ->
          assert {:error, :unsupported_era} = Response.decode(cbor_data)
        end)

      assert log =~ "Could not parse block"
      assert log =~ "Only conway era formats are currently supported"
    end

    test "returns error for invalid CBOR in header bytes" do
      invalid_inner_cbor = <<0x83, 0x01, 0x02>>

      header = %CBOR.Tag{
        tag: @encoded_cbor_data_tag,
        value: %CBOR.Tag{
          tag: :bytes,
          value: invalid_inner_cbor
        }
      }

      # Build tip
      block_bytes = :crypto.strong_rand_bytes(32)

      tip = [
        [12345, %CBOR.Tag{tag: :bytes, value: block_bytes}],
        100
      ]

      cbor_data = CBOR.encode([2, header, tip])
      assert {:error, _reason} = Response.decode(cbor_data)
    end
  end

  describe "block hash encoding" do
    test "hash is lowercase hex encoded" do
      # Create a known block bytes value
      block_bytes = <<0xAB, 0xCD, 0xEF, 0x12, 0x34>>

      point_slot_number = 1000

      point = [
        point_slot_number,
        %CBOR.Tag{tag: :bytes, value: block_bytes}
      ]

      tip_block_bytes = :crypto.strong_rand_bytes(32)

      tip = [
        [2000, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
        100
      ]

      cbor_data = CBOR.encode([5, point, tip])

      assert {:ok, %IntersectFound{point: parsed_point}} = Response.decode(cbor_data)

      # Verify hash is lowercase hex
      assert parsed_point.hash == "abcdef1234"
      assert parsed_point.hash == String.downcase(parsed_point.hash)
    end
  end
end

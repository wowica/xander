defmodule Xander.CBOR do
  # See https://www.rfc-editor.org/rfc/rfc8949.html#section-3.4
  @encoded_cbor_data_tag 24

  defmodule IntersectFound do
    defstruct [:point, :tip]
  end

  defmodule RollBackward do
    defstruct [:point, :tip]
  end

  defmodule RollForward do
    defstruct [:header, :tip]
  end

  defmodule AwaitReply do
    defstruct []
  end

  def decode(cbor_data) do
    case CBOR.decode(cbor_data) do
      {:ok, [1], _rest} ->
        {:ok, %AwaitReply{}}

      {:ok, [2, header, tip], _rest} ->
        {:ok, %RollForward{header: header, tip: tip}}

      {:ok, [3, point, tip], _rest} ->
        {:ok, %RollBackward{point: point, tip: tip}}

      {:ok, [5, point, tip], _rest} ->
        {:ok, %IntersectFound{point: point, tip: tip}}

      {:error, _} ->
        {:error, :incomplete_cbor_data}

      something_else ->
        something_else
    end
  end

  def decode_header(header) do
    %CBOR.Tag{
      tag: @encoded_cbor_data_tag,
      value: %CBOR.Tag{
        tag: :bytes,
        value: header_bytes
      }
    } = header

    case CBOR.decode(header_bytes) do
      {:ok, [_idk_what_this_is, [[[block_number | _] | _] | _] | _signature], _rest} ->
        {:ok, %{block_number: block_number, header_bytes: header_bytes}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def decode_block(block) do
    [[slot_number, block_payload], _block_height] = block

    %CBOR.Tag{
      tag: :bytes,
      value: block_bytes
    } = block_payload

    {:ok,
     %{
       block_bytes: block_bytes,
       block_hash: Base.encode16(block_bytes, case: :lower),
       slot_number: slot_number
     }}
  end

  def decode_point(point) do
    [
      rollback_slot_number,
      %CBOR.Tag{tag: :bytes, value: rollback_block_bytes}
    ] = point

    rollback_block_hash = Base.encode16(rollback_block_bytes, case: :lower)

    {:ok,
     %{
       block_bytes: rollback_block_bytes,
       block_hash: rollback_block_hash,
       slot_number: rollback_slot_number
     }}
  end
end

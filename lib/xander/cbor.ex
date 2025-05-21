defmodule Xander.CBOR do
  defdelegate decode(data), to: CBOR

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
end

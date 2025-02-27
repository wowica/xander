# Monkey patch for CBOR.Encoder to properly set 2 when encoding a binary
# https://www.rfc-editor.org/rfc/rfc8949.html#section-3.1
defimpl CBOR.Encoder, for: BitString do
  @major_type_byte_string 2
  @major_type_text_string 3

  def encode_into(s, acc) when is_binary(s) do
    CBOR.Utils.encode_string(@major_type_byte_string, s, acc)
  end

  def encode_into(s, acc) do
    CBOR.Utils.encode_string(@major_type_text_string, s, acc)
  end
end

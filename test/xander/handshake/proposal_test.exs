defmodule Xander.Handshake.ProposalTest do
  use ExUnit.Case
  alias Xander.Handshake

  # <<45, 150, 74, 9>>
  @mainnet_magic 764_824_073

  # These 16 bits represent the M value (0 for initiator) and the protocol ID (0 for Handshake)
  @protocol_id <<0, 0>>

  describe "version_message/2" do
    test "builds the correct message for versions 10 and up on mainnet" do
      <<_timestamps_lower_32::binary-size(4), @protocol_id, payload_size::binary-size(2),
        payload::binary>> =
        Handshake.Proposal.version_message([10, 11, 12, 13, 14, 15, 16], :mainnet)

      {:ok, message, ""} = CBOR.decode(payload)

      assert payload_size == <<0, 63>>

      assert message == [
               0,
               %{
                 32778 => @mainnet_magic,
                 32779 => @mainnet_magic,
                 32780 => @mainnet_magic,
                 32781 => @mainnet_magic,
                 32782 => @mainnet_magic,
                 32783 => [@mainnet_magic, false],
                 32784 => [@mainnet_magic, false]
               }
             ]
    end
  end
end

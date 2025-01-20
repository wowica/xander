defmodule Mix.Tasks.Dev do
  use Mix.Task

  alias Xander.Handshake

  def run(_) do
    Application.ensure_all_started(:xander)

    msg = Handshake.Proposal.version_message([10, 11, 12, 13, 14, 15, 16], :mainnet)

    dbg(msg)
    dbg(CBOR.decode(msg))

    :ok
  end
end

defmodule Xander.Transaction.Hash do
  @moduledoc """
  Extracts a transaction ID from a transaction CBOR hex.
  """

  require Logger

  @doc """
  Extracts a transaction ID from a transaction CBOR hex.
  Returns the transaction ID as a string, or nil if there's an error.

  ## Examples

      # Valid transaction hash
      iex> Xander.Transaction.Hash.get_id("84a500d901028182582015e6ff205f08b2a29371e97b876e62ef942e5b8b74331d0e1cc735b5945d32bc02018282583900f9a2fa2e3fb59bbf8cfda38437c391fc3047e56a3b7c37e5f7a5fbd12d2915e78d60e700f34154074b6ec1cd365531f196276748ba498f251a00b71b0082583900f9a2fa2e3fb59bbf8cfda38437c391fc3047e56a3b7c37e5f7a5fbd12d2915e78d60e700f34154074b6ec1cd365531f196276748ba498f251a246d92ef021a000292dd031a0481bdd00800a100d9010281825820439c9a6aa2b4533d7a8309326f644998b8e8b42f22b8850fa858a93fc7e2888e584089bc8da32942758efdba2779daa6252e00c06bfc76b5a1b144d33e5d01b3f5c75ca45e784005ce73f839cf8c6bf0851552daabe13b94ad95997de91c66ae5b06f5f6")
      "dc2d59c0188d55a94fc4780b930276d49303b558534dedbdfe7aca1c995cf463"

      # Invalid transaction hash
      iex> Xander.Transaction.Hash.get_id("84a500d9123")
      nil
  """
  @spec get_id(String.t()) :: String.t() | nil
  def get_id(cbor_hash) do
    try do
      cbor_hash = String.upcase(cbor_hash)
      {:ok, transaction} = Base.decode16(cbor_hash)
      {:ok, [tx_body | _], ""} = CBOR.decode(transaction)

      tx_body
      |> CBOR.encode()
      # Blake2b-256 is currently not supported by the built-in :crypto module
      # so we must use the :blake2 dependency.
      |> Blake2.hash2b(32)
      |> Base.encode16(case: :lower)
    rescue
      error ->
        Logger.warning("Error extracting tx id: #{inspect(error)}")
        nil
    end
  end
end

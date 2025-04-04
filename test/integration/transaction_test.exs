defmodule Xander.Integration.TransactionTest do
  use ExUnit.Case
  alias Xander.Config
  # alias Xander.Query
  alias Xander.Transaction

  @mnemonic "test test test test test test test test test test test test test test test test test test test test test test test sauce"

  @address0 "addr_test1qryvgass5dsrf2kxl3vgfz76uhp83kv5lagzcp29tcana68ca5aqa6swlq6llfamln09tal7n5kvt4275ckwedpt4v7q48uhex"
  @utxo0 "6d36c0e2f304a5c27b85b3f04e95fc015566d35aef5f061c17c70e3e8b9ee508#0"

  @address1 "addr_test1qpqy3lufef8c3en9nrnzp2svwy5vy9zangvp46dy4qw23clgfxhn3pqv243d6wptud7fuaj5tjqer7wc7m036gx0emsqaqa8te"
  @utxo1 "dc0d0d0a13e683e443c575147ec12136e5ac6a4f994cd4189d4d25bed541c44d#0"

  @address2 "addr_test1qr9xuxclxgx4gw3y4h4tcz4yvfmrt3e5nd3elphhf00a67xnrv5vjcv6tzehj2nnjj4cth4ndzyuf4asvvkgzeac2hfqk0za93"
  @utxo2 "aae852d5d2b08c0a937a319fec0d9933bc3bc67b9d0a6bfd4001997b169364b3#0"

  @address3 "addr_test1qqra0q073cecs03hr724psh3ppejrlpjuphgpdj7xjwvkqnhqttgsr5xuaaq2g805dldu3gq9gw7gwmgdyhpwkm59ensgyph06"
  @utxo3 "145da89c02380f6f72d6acc8194cd9295eb2001c2d88f0b20fef647ec5a18f7f#0"

  setup do
    # Create a temporary directory for our transaction files
    tmp_dir = System.tmp_dir!()
    tx_dir = Path.join(tmp_dir, "tx_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tx_dir)

    # Generate test keys
    keys_dir = Path.join(tx_dir, "keys")
    File.mkdir_p!(keys_dir)

    # Generate payment key pair
    {_output, 0} =
      System.cmd("cardano-cli", [
        "address",
        "key-gen",
        "--verification-key-file",
        Path.join(keys_dir, "payment.vkey"),
        "--signing-key-file",
        Path.join(keys_dir, "payment.skey")
      ])

    # Generate stake key pair
    {_output, 0} =
      System.cmd("cardano-cli", [
        "stake-address",
        "key-gen",
        "--verification-key-file",
        Path.join(keys_dir, "stake.vkey"),
        "--signing-key-file",
        Path.join(keys_dir, "stake.skey")
      ])

    # Build address
    {output, 0} =
      System.cmd("cardano-cli", [
        "address",
        "build",
        "--payment-verification-key-file",
        Path.join(keys_dir, "payment.vkey"),
        "--stake-verification-key-file",
        Path.join(keys_dir, "stake.vkey"),
        "--out-file",
        Path.join(keys_dir, "address.addr"),
        "--testnet-magic",
        "2"
      ])

    # Read the generated address
    {:ok, address} = File.read(Path.join(keys_dir, "address.addr"))
    address = String.trim(address)

    on_exit(fn ->
      File.rm_rf!(tx_dir)
    end)

    %{
      tx_dir: tx_dir,
      keys_dir: keys_dir,
      address: address
    }
  end

  @tag :integration
  test "can perform basic transactions to transfer ADA", %{
    tx_dir: tx_dir,
    keys_dir: keys_dir,
    address: address
  } do
    # Set up network parameters
    network = "testnet"
    protocol_params = Path.join(tx_dir, "protocol-params.json")

    # Get protocol parameters
    {output, 0} =
      System.cmd("cardano-cli", [
        "query",
        "protocol-parameters",
        "--#{network}",
        "--out-file",
        protocol_params
      ])

    # Create a transaction
    tx_out = Path.join(tx_dir, "tx.out")
    tx_signed = Path.join(tx_dir, "tx.signed")

    # Build the transaction
    # Transfer 1000000 lovelace (1 ADA) from our generated address to address1
    {output, 0} =
      System.cmd("cardano-cli", [
        "transaction",
        "build",
        "--#{network}",
        "--tx-in",
        @utxo0,
        "--tx-out",
        "#{@address1}+1000000",
        "--change-address",
        address,
        "--protocol-params-file",
        protocol_params,
        "--out-file",
        tx_out
      ])

    # Sign the transaction
    {output, 0} =
      System.cmd("cardano-cli", [
        "transaction",
        "sign",
        "--#{network}",
        "--tx-body-file",
        tx_out,
        "--signing-key-file",
        Path.join(keys_dir, "payment.skey"),
        "--out-file",
        tx_signed
      ])

    # Submit the transaction
    {output, 0} =
      System.cmd("cardano-cli", [
        "transaction",
        "submit",
        "--#{network}",
        "--tx-file",
        tx_signed
      ])

    # Verify the transaction was submitted successfully
    assert output =~ "Transaction successfully submitted"
  end

  # @tag :integration
  # test "can connect to a local node and query current era" do
  #   # This test requires a running Cardano node
  #   socket_path = System.get_env("CARDANO_NODE_SOCKET_PATH", "/tmp/cardano-node.socket")

  #   config = Config.default_config!(socket_path)

  #   assert {:ok, pid} = Query.start_link(config)
  #   assert {:ok, era} = Query.run(pid, :get_current_era)
  #   assert is_integer(era)
  # end

  # @tag :integration
  # test "can connect to Demeter and query current era" do
  #   # This test requires Demeter credentials
  #   demeter_url = System.get_env("DEMETER_URL")
  #   if demeter_url == nil, do: flunk("DEMETER_URL environment variable is not set")

  #   config = Config.demeter_config!(demeter_url)

  #   assert {:ok, pid} = Query.start_link(config)
  #   assert {:ok, era} = Query.run(pid, :get_current_era)
  #   assert is_integer(era)
  # end
end

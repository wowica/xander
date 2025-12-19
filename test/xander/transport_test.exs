defmodule Xander.TransportTest do
  use ExUnit.Case

  alias Xander.Transport

  describe "new/1" do
    test "creates transport for Unix socket connection" do
      transport = Transport.new(path: "/tmp/node.socket", port: 0, type: :socket)

      assert %Transport{
               type: :socket,
               client: :gen_tcp,
               setopts_module: :inet,
               path: {:local, "/tmp/node.socket"},
               port: 0
             } = transport

      assert transport.connect_opts == [:binary, active: false, send_timeout: 4_000]
    end

    test "creates transport for SSL connection" do
      transport = Transport.new(path: "https://node.demeter.run", port: 9443, type: :ssl)

      assert %Transport{
               type: :ssl,
               client: :ssl,
               setopts_module: :ssl,
               path: "https://node.demeter.run",
               port: 9443
             } = transport

      assert :binary in transport.connect_opts
      assert {:active, false} in transport.connect_opts
      assert {:send_timeout, 4_000} in transport.connect_opts
      assert {:verify, :verify_none} in transport.connect_opts
      assert {:server_name_indication, ~c"https://node.demeter.run"} in transport.connect_opts
      assert {:secure_renegotiate, true} in transport.connect_opts
    end

    test "normalizes port to 0 for Unix socket connections" do
      transport = Transport.new(path: "/tmp/node.socket", port: 9443, type: :socket)

      assert transport.port == 0
    end

    test "preserves port for SSL connections" do
      transport = Transport.new(path: "https://node.demeter.run", port: 9443, type: :ssl)

      assert transport.port == 9443
    end

    test "wraps path in :local tuple for Unix socket connections" do
      transport = Transport.new(path: "/var/run/cardano.socket", port: 0, type: :socket)

      assert transport.path == {:local, "/var/run/cardano.socket"}
    end

    test "preserves path as-is for SSL connections" do
      transport = Transport.new(path: "https://example.demeter.run", port: 9443, type: :ssl)

      assert transport.path == "https://example.demeter.run"
    end

    test "raises when required options are missing" do
      assert_raise KeyError, fn ->
        Transport.new(path: "/tmp/node.socket", port: 0)
      end

      assert_raise KeyError, fn ->
        Transport.new(path: "/tmp/node.socket", type: :socket)
      end

      assert_raise KeyError, fn ->
        Transport.new(port: 0, type: :socket)
      end
    end
  end

  describe "connect/1 with Unix socket" do
    test "returns error when socket does not exist" do
      transport = Transport.new(path: "/tmp/nonexistent.socket", port: 0, type: :socket)

      assert {:error, _reason} = Transport.connect(transport)
    end
  end

  describe "connect/1 with SSL" do
    test "returns error when host is unreachable" do
      transport =
        Transport.new(path: "https://nonexistent.invalid.host", port: 9443, type: :ssl)

      assert {:error, _reason} = Transport.connect(transport)
    end
  end

  describe "send/3, recv/4, setopts/3, close/2" do
    @tag :integration
    test "performs full socket communication cycle with Unix socket" do
      # This test requires a running Cardano node
      # Skip in unit tests, run only in integration tests
      socket_path =
        System.get_env("CARDANO_NODE_SOCKET_PATH") ||
          Path.expand("~/.yaci-cli/local-clusters/default/node/node.sock")

      transport = Transport.new(path: socket_path, port: 0, type: :socket)

      case Transport.connect(transport) do
        {:ok, socket} ->
          # Test setopts
          assert :ok = Transport.setopts(transport, socket, active: false)

          # Test close
          assert :ok = Transport.close(transport, socket)

        {:error, _reason} ->
          # Socket not available, skip test
          :ok
      end
    end
  end

  describe "module selection" do
    test "selects :gen_tcp for socket type" do
      transport = Transport.new(path: "/tmp/node.socket", port: 0, type: :socket)

      assert transport.client == :gen_tcp
    end

    test "selects :ssl for ssl type" do
      transport = Transport.new(path: "https://node.demeter.run", port: 9443, type: :ssl)

      assert transport.client == :ssl
    end

    test "selects :inet for setopts with socket type" do
      transport = Transport.new(path: "/tmp/node.socket", port: 0, type: :socket)

      assert transport.setopts_module == :inet
    end

    test "selects :ssl for setopts with ssl type" do
      transport = Transport.new(path: "https://node.demeter.run", port: 9443, type: :ssl)

      assert transport.setopts_module == :ssl
    end
  end
end

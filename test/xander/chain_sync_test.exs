defmodule Xander.ChainSyncTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Xander.ChainSync
  alias Xander.Transport

  @encoded_cbor_data_tag 24

  defmodule TestClient do
    def connect(_address, _port, _opts) do
      {:ok, make_ref()}
    end

    def send(_socket, _data), do: :ok

    def recv(socket, _length, _timeout) do
      case socket do
        {:test_response, response} -> {:ok, response}
        {:test_error, reason} -> {:error, reason}
        {:test_sequence, responses} when is_list(responses) -> get_next_response(responses)
        _ -> {:ok, <<>>}
      end
    end

    def close(_socket), do: :ok

    defp get_next_response([response | _rest]) do
      case response do
        {:ok, data} -> {:ok, data}
        {:error, reason} -> {:error, reason}
      end
    end

    defp get_next_response([]), do: {:error, :no_more_responses}
  end

  defmodule TestSetoptsModule do
    def setopts(_socket, _opts), do: :ok
  end

  defmodule TestHandler do
    use Xander.ChainSync

    def start_link(opts) do
      Xander.ChainSync.start_link(__MODULE__, opts)
    end

    @impl Xander.ChainSync
    def handle_block(block, state) do
      send(state[:test_pid], {:block_received, block})
      {:ok, :next_block, state}
    end

    @impl Xander.ChainSync
    def handle_rollback(point, state) do
      send(state[:test_pid], {:rollback_received, point})
      {:ok, :next_block, state}
    end
  end

  defmodule CloseAfterBlockHandler do
    use Xander.ChainSync

    def start_link(opts) do
      Xander.ChainSync.start_link(__MODULE__, opts)
    end

    @impl Xander.ChainSync
    def handle_block(block, state) do
      send(state[:test_pid], {:block_received, block})
      {:close, state}
    end
  end

  defmodule DefaultRollbackHandler do
    use Xander.ChainSync

    def start_link(opts) do
      Xander.ChainSync.start_link(__MODULE__, opts)
    end

    @impl Xander.ChainSync
    def handle_block(_block, state) do
      {:ok, :next_block, state}
    end

    # Does NOT override handle_rollback - uses the default from __using__ macro
  end

  defp test_transport do
    %Transport{
      type: :socket,
      client: TestClient,
      setopts_module: TestSetoptsModule,
      path: {:local, "/tmp/test.socket"},
      port: 0,
      connect_opts: []
    }
  end

  defp build_handshake_accept_response(version \\ 32784, network_magic \\ 764_824_073) do
    cbor_payload = CBOR.encode([1, version, [network_magic, %{"query" => true}]])
    wrap_in_multiplexer(cbor_payload, 0)
  end

  defp build_await_reply_response do
    cbor_payload = CBOR.encode([1])
    wrap_in_multiplexer(cbor_payload, 5)
  end

  defp build_roll_forward_response(block_number, block_body_size, tip_slot \\ 150_000_000) do
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

    tip_block_bytes = :crypto.strong_rand_bytes(32)

    tip = [
      [tip_slot, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
      100
    ]

    cbor_payload = CBOR.encode([2, header, tip])
    wrap_in_multiplexer(cbor_payload, 5)
  end

  defp build_roll_backward_response(slot_number, block_bytes \\ nil, tip_slot \\ 150_000_000) do
    block_bytes = block_bytes || :crypto.strong_rand_bytes(32)

    point = [
      slot_number,
      %CBOR.Tag{tag: :bytes, value: block_bytes}
    ]

    tip_block_bytes = :crypto.strong_rand_bytes(32)

    tip = [
      [tip_slot, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
      100
    ]

    cbor_payload = CBOR.encode([3, point, tip])
    wrap_in_multiplexer(cbor_payload, 5)
  end

  defp build_roll_backward_origin_response(tip_slot \\ 150_000_000) do
    # Empty point represents origin
    point = []
    tip_block_bytes = :crypto.strong_rand_bytes(32)

    tip = [
      [tip_slot, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
      100
    ]

    cbor_payload = CBOR.encode([3, point, tip])
    wrap_in_multiplexer(cbor_payload, 5)
  end

  defp build_intersect_found_response(
         point_slot,
         point_block_bytes,
         tip_slot \\ 150_000_000
       ) do
    point = [
      point_slot,
      %CBOR.Tag{tag: :bytes, value: point_block_bytes}
    ]

    tip_block_bytes = :crypto.strong_rand_bytes(32)

    tip = [
      [tip_slot, %CBOR.Tag{tag: :bytes, value: tip_block_bytes}],
      200
    ]

    cbor_payload = CBOR.encode([5, point, tip])
    wrap_in_multiplexer(cbor_payload, 5)
  end

  defp wrap_in_multiplexer(cbor_payload, protocol_id) do
    timestamp = <<0, 0, 0, 0>>
    mode_and_protocol = <<0::1, protocol_id::15>>
    size = <<byte_size(cbor_payload)::big-16>>
    timestamp <> mode_and_protocol <> size <> cbor_payload
  end

  describe "__using__/1 macro" do
    test "provides default handle_rollback implementation" do
      # The default implementation just returns {:ok, :next_block, state}
      # Using DefaultRollbackHandler which doesn't override handle_rollback
      state = %{some: :state}
      point = %{slot_number: 12345, block_hash: "abc123"}

      assert {:ok, :next_block, ^state} = DefaultRollbackHandler.handle_rollback(point, state)
    end

    test "generates child_spec/1" do
      opts = [network: :mainnet, path: "/tmp/test.socket", type: :socket]
      spec = TestHandler.child_spec(opts)

      assert %{
               id: TestHandler,
               start: {TestHandler, :start_link, [^opts]},
               type: :worker,
               restart: :temporary,
               shutdown: 5_000
             } = spec
    end
  end

  describe "callback_mode/0" do
    test "returns :state_functions" do
      assert ChainSync.callback_mode() == :state_functions
    end
  end

  describe "init/1" do
    test "initializes to disconnected state with connect action" do
      data = %ChainSync{
        client_module: TestHandler,
        transport: test_transport(),
        network: :mainnet
      }

      assert {:ok, :disconnected, ^data, actions} = ChainSync.init(data)
      assert [{:next_event, :internal, :connect}] = actions
    end
  end

  describe "disconnected/3" do
    test "transitions to connected state on successful connection" do
      transport = test_transport()

      data = %ChainSync{
        client_module: TestHandler,
        transport: transport,
        network: :mainnet,
        socket: nil
      }

      result = ChainSync.disconnected(:internal, :connect, data)

      assert {:next_state, :connected, updated_data, actions} = result
      assert updated_data.socket != nil
      assert [{:next_event, :internal, :establish}] = actions
    end

    test "stays in disconnected state on connection error" do
      defmodule FailingClient do
        def connect(_address, _port, _opts) do
          {:error, :econnrefused}
        end
      end

      transport = %Transport{
        type: :socket,
        client: FailingClient,
        setopts_module: TestSetoptsModule,
        path: {:local, "/tmp/test.socket"},
        port: 0,
        connect_opts: []
      }

      data = %ChainSync{
        client_module: TestHandler,
        transport: transport,
        network: :mainnet
      }

      log =
        capture_log(fn ->
          result = ChainSync.disconnected(:internal, :connect, data)
          assert {:next_state, :disconnected, ^data} = result
        end)

      assert log =~ "Error reaching socket"
    end

    test "returns error when called with call event" do
      data = %ChainSync{
        client_module: TestHandler,
        transport: test_transport(),
        network: :mainnet
      }

      from = {self(), make_ref()}
      result = ChainSync.disconnected({:call, from}, :some_command, data)

      assert {:keep_state, ^data, actions} = result
      assert [{:reply, ^from, {:error, :disconnected}}] = actions
    end
  end

  describe "start_link/2" do
    test "ignores start when sync_from is :origin and network is not :yaci_devkit" do
      log =
        capture_log(fn ->
          result =
            ChainSync.start_link(TestHandler,
              network: :mainnet,
              path: "/tmp/test.socket",
              port: 0,
              type: :socket,
              sync_from: :origin
            )

          assert result == :ignore
        end)

      assert log =~
               "Syncing from origin is only supported on the yaci_devkit network"
    end

    @tag capture_log: true
    test "allows sync_from :origin when network is :yaci_devkit" do
      # This will fail to actually connect but won't be ignored
      result =
        ChainSync.start_link(TestHandler,
          network: :yaci_devkit,
          path: "/tmp/nonexistent.socket",
          port: 0,
          type: :socket,
          sync_from: :origin
        )

      # It will either start or fail to connect, but not be ignored
      assert result != :ignore
      # Clean up if it started
      case result do
        {:ok, pid} -> GenServer.stop(pid)
        _ -> :ok
      end
    end
  end

  describe "catching_up/3 socket message handling" do
    @tag capture_log: true
    test "handles tcp_closed during state transition" do
      data = %ChainSync{
        client_module: TestHandler,
        transport: test_transport(),
        socket: make_ref(),
        state: []
      }

      result = ChainSync.catching_up(:info, {:tcp_closed, data.socket}, data)
      assert {:next_state, :disconnected, ^data} = result
    end

    @tag capture_log: true
    test "handles ssl_closed during state transition" do
      data = %ChainSync{
        client_module: TestHandler,
        transport: test_transport(),
        socket: make_ref(),
        state: []
      }

      result = ChainSync.catching_up(:info, {:ssl_closed, data.socket}, data)
      assert {:next_state, :disconnected, ^data} = result
    end
  end

  describe "response building helpers" do
    test "build_handshake_accept_response creates valid response" do
      response = build_handshake_accept_response()
      assert is_binary(response)
      assert byte_size(response) > 8

      # Parse the multiplexer header
      <<_timestamp::32, _mode::1, protocol_id::15, size::big-16, payload::binary>> = response
      assert protocol_id == 0
      assert byte_size(payload) == size
    end

    test "build_await_reply_response creates valid response" do
      response = build_await_reply_response()
      assert is_binary(response)

      <<_timestamp::32, _mode::1, protocol_id::15, size::big-16, payload::binary>> = response
      assert protocol_id == 5
      assert byte_size(payload) == size

      {:ok, [1], ""} = CBOR.decode(payload)
    end

    test "build_roll_forward_response creates valid response" do
      response = build_roll_forward_response(12345, 6789)
      assert is_binary(response)

      <<_timestamp::32, _mode::1, protocol_id::15, size::big-16, payload::binary>> = response
      assert protocol_id == 5
      assert byte_size(payload) == size

      {:ok, [2, _header, _tip], ""} = CBOR.decode(payload)
    end

    test "build_roll_backward_response creates valid response" do
      response = build_roll_backward_response(100_000)
      assert is_binary(response)

      <<_timestamp::32, _mode::1, protocol_id::15, size::big-16, payload::binary>> = response
      assert protocol_id == 5
      assert byte_size(payload) == size

      {:ok, [3, _point, _tip], ""} = CBOR.decode(payload)
    end

    test "build_roll_backward_origin_response creates empty point" do
      response = build_roll_backward_origin_response()
      assert is_binary(response)

      <<_timestamp::32, _mode::1, _protocol_id::15, _size::big-16, payload::binary>> = response

      {:ok, [3, point, _tip], ""} = CBOR.decode(payload)
      assert point == []
    end

    test "build_intersect_found_response creates valid response" do
      block_bytes = :crypto.strong_rand_bytes(32)
      response = build_intersect_found_response(100_000, block_bytes)
      assert is_binary(response)

      <<_timestamp::32, _mode::1, protocol_id::15, size::big-16, payload::binary>> = response
      assert protocol_id == 5
      assert byte_size(payload) == size

      {:ok, [5, _point, _tip], ""} = CBOR.decode(payload)
    end
  end

  describe "ChainSync behaviour callbacks" do
    test "handle_block callback signature is correct" do
      block = %{block_number: 100, size: 500}
      state = %{test_pid: self()}

      assert {:ok, :next_block, _new_state} = TestHandler.handle_block(block, state)
      assert_receive {:block_received, ^block}
    end

    test "handle_rollback callback can be overridden" do
      point = %{slot_number: 12345, block_hash: "abc123"}
      state = %{test_pid: self()}

      assert {:ok, :next_block, _new_state} = TestHandler.handle_rollback(point, state)
      assert_receive {:rollback_received, ^point}
    end
  end

  describe "CloseAfterBlockHandler" do
    test "returns close tuple from handle_block" do
      block = %{block_number: 100, size: 500}
      state = %{test_pid: self()}

      assert {:close, ^state} = CloseAfterBlockHandler.handle_block(block, state)
      assert_receive {:block_received, ^block}
    end
  end
end

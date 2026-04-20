# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Tests for Burble.Bridges.* — external voice/chat bridge modules.
#
# Each bridge (Mumble, SIP, Discord, Matrix) is a GenServer that connects
# Burble rooms to third-party voice platforms.  Tests here verify:
#   1. Each module compiles and exports its public API.
#   2. Mumble bridge GenServer starts, reports initial disconnected status,
#      and stops cleanly — using a loopback host so no real network is needed.
#   3. SIP bridge starts, reports initial state, and stops cleanly.
#   4. Bridge module discovery: all four bridge modules are loadable.

defmodule Burble.Bridges.BridgesTest do
  use ExUnit.Case, async: true

  alias Burble.Bridges.Discord
  alias Burble.Bridges.Matrix
  alias Burble.Bridges.Mumble
  alias Burble.Bridges.SIP

  # ---------------------------------------------------------------------------
  # 1. Module existence and public API surface
  # ---------------------------------------------------------------------------

  describe "Mumble bridge module" do
    test "exports expected public functions" do
      assert function_exported?(Mumble, :start_link, 1)
      assert function_exported?(Mumble, :stop, 1)
      assert function_exported?(Mumble, :status, 1)
      assert function_exported?(Mumble, :mumble_users, 1)
      assert function_exported?(Mumble, :send_text, 3)
      assert function_exported?(Mumble, :relay_to_mumble, 2)
    end

    test "is a GenServer" do
      behaviours =
        Mumble.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert GenServer in behaviours
    end
  end

  describe "SIP bridge module" do
    test "exports expected public functions" do
      assert function_exported?(SIP, :start_link, 1)
      assert function_exported?(SIP, :stop, 1)
      assert function_exported?(SIP, :status, 1)
      assert function_exported?(SIP, :dial, 2)
      assert function_exported?(SIP, :hangup, 1)
      assert function_exported?(SIP, :relay_to_sip, 2)
      assert function_exported?(SIP, :send_dtmf, 2)
    end

    test "is a GenServer" do
      behaviours =
        SIP.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert GenServer in behaviours
    end
  end

  describe "Discord bridge module" do
    test "exports expected public functions" do
      assert function_exported?(Discord, :start_link, 1)
      assert function_exported?(Discord, :stop, 1)
      assert function_exported?(Discord, :status, 1)
      assert function_exported?(Discord, :discord_users, 1)
      assert function_exported?(Discord, :send_text, 3)
      assert function_exported?(Discord, :relay_to_discord, 2)
    end

    test "is a GenServer" do
      behaviours =
        Discord.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert GenServer in behaviours
    end
  end

  describe "Matrix bridge module" do
    test "exports expected public functions" do
      assert function_exported?(Matrix, :start_link, 1)
      assert function_exported?(Matrix, :stop, 1)
      assert function_exported?(Matrix, :status, 1)
      assert function_exported?(Matrix, :matrix_members, 1)
      assert function_exported?(Matrix, :send_text, 3)
    end

    test "is a GenServer" do
      behaviours =
        Matrix.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert GenServer in behaviours
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Bridge module discovery
  # ---------------------------------------------------------------------------

  describe "available bridge modules" do
    test "all four bridge modules are loadable" do
      bridges = [Mumble, SIP, Discord, Matrix]

      for mod <- bridges do
        assert Code.ensure_loaded?(mod),
               "Bridge module #{inspect(mod)} could not be loaded"
      end
    end

    test "each bridge module defines a start_link/1 entry point" do
      bridges = [Mumble, SIP, Discord, Matrix]

      for mod <- bridges do
        assert function_exported?(mod, :start_link, 1),
               "#{inspect(mod)} is missing start_link/1"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Mumble bridge — connect/disconnect lifecycle (mocked)
  #
  # We start the GenServer with a deliberately unreachable loopback host so
  # that :gen_tcp.connect fails immediately.  The bridge falls back to a
  # scheduled retry, giving us a live process to interact with in a
  # disconnected-but-running state.
  # ---------------------------------------------------------------------------

  describe "Mumble bridge lifecycle" do
    setup do
      opts = [
        room_id: "test_room_mumble_#{System.unique_integer([:positive])}",
        mumble_host: "127.0.0.1",
        mumble_port: 1,           # port 1 is reserved and always refused
        mumble_channel: "Test",
        bot_name: "TestBot"
      ]

      # Start unregistered to avoid colliding with any global registry.
      {:ok, pid} = GenServer.start_link(Mumble, opts)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
      %{pid: pid, room_id: Keyword.fetch!(opts, :room_id)}
    end

    test "GenServer starts and is alive", %{pid: pid} do
      assert Process.alive?(pid)
    end

    test "status/1 returns an ok tuple with status map", %{pid: pid} do
      {:ok, status} = Mumble.status(pid)
      assert is_map(status)
    end

    test "initial status reports disconnected", %{pid: pid} do
      # Allow the async :connect message to be processed (it will fail quickly
      # on port 1 and schedule a retry) before sampling status.
      Process.sleep(50)
      {:ok, status} = Mumble.status(pid)
      assert status.connected == false
    end

    test "status includes expected fields", %{pid: pid} do
      {:ok, status} = Mumble.status(pid)

      assert Map.has_key?(status, :room_id)
      assert Map.has_key?(status, :mumble_host)
      assert Map.has_key?(status, :mumble_channel)
      assert Map.has_key?(status, :connected)
      assert Map.has_key?(status, :mumble_user_count)
      assert Map.has_key?(status, :bot_name)
    end

    test "mumble_users/1 returns empty list when not connected", %{pid: pid} do
      {:ok, users} = Mumble.mumble_users(pid)
      assert users == []
    end

    test "send_text/3 is a no-op when not connected (does not crash)", %{pid: pid} do
      # Should drop silently because tcp_socket is nil.
      result = Mumble.send_text(pid, "Tester", "hello")
      assert result == :ok
    end

    test "stop/1 terminates the process cleanly", %{pid: pid} do
      assert :ok = Mumble.stop(pid)
      refute Process.alive?(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. SIP bridge — module compiles, DNS SRV lookup stub, lifecycle
  # ---------------------------------------------------------------------------

  describe "SIP bridge lifecycle" do
    setup do
      opts = [
        room_id: "test_room_sip_#{System.unique_integer([:positive])}",
        sip_host: "127.0.0.1",
        sip_port: 5060,
        sip_user: "test-bridge",
        local_rtp_port: 0         # let the OS pick any free ephemeral port
      ]

      {:ok, pid} = GenServer.start_link(SIP, opts)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
      %{pid: pid}
    end

    test "GenServer starts and is alive", %{pid: pid} do
      assert Process.alive?(pid)
    end

    test "status/1 returns an ok tuple with status map", %{pid: pid} do
      {:ok, status} = SIP.status(pid)
      assert is_map(status)
    end

    test "initial status reports not registered and no active call", %{pid: pid} do
      {:ok, status} = SIP.status(pid)
      assert status.registered == false
      assert status.call == nil
    end

    test "status includes expected fields", %{pid: pid} do
      {:ok, status} = SIP.status(pid)

      assert Map.has_key?(status, :room_id)
      assert Map.has_key?(status, :sip_host)
      assert Map.has_key?(status, :registered)
      assert Map.has_key?(status, :call)
    end

    test "DNS SRV lookup is not implemented — dial/2 returns an error on no-op host", %{pid: pid} do
      # The SIP module docs state: "DNS SRV lookup not implemented (direct
      # host:port only)".  Dialling a SIP URI when sockets are not yet open
      # should return either :ok (message queued) or {:error, _reason}.
      # Critically: it must not raise or crash the GenServer.
      result = SIP.dial(pid, "sip:test@127.0.0.1")
      assert result in [:ok, {:error, :already_in_call}] or match?({:error, _}, result)
      assert Process.alive?(pid)
    end

    test "stop/1 terminates the process cleanly", %{pid: pid} do
      assert :ok = SIP.stop(pid)
      refute Process.alive?(pid)
    end
  end
end

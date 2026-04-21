# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble.Bolt.Listener — UDP GenServer that receives incoming Bolt packets.
#
# Binds to UDP port 7373 (Burble Bolt port). When a valid Bolt packet arrives,
# it is decoded and forwarded to Burble.Bolt.Notify which broadcasts it via
# Phoenix.PubSub and triggers the desktop/browser incoming-call notification.
#
# QUIC transport: if the :quicer application is available (optional dep),
# Burble Bolt will also accept QUIC datagrams on port 7373 alongside raw UDP.
# QUIC datagrams (RFC 9221) provide the same unreliable delivery semantics as
# UDP but with TLS 1.3 authentication — the sender is cryptographically verified.

defmodule Burble.Bolt.Listener do
  use GenServer
  require Logger

  alias Burble.Bolt.{Packet, Notify}

  @port Packet.port()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the UDP port this listener is bound to."
  def port, do: @port

  @doc "Returns `{:ok, :udp | :quic}` indicating the active transport."
  def transport do
    GenServer.call(__MODULE__, :transport)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    port = opts[:port] || @port

    case open_socket(port) do
      {:ok, socket, transport} ->
        Logger.info("[Bolt] Listener active on UDP port #{port} (transport: #{transport})")
        {:ok, %{socket: socket, port: port, transport: transport}}

      {:error, reason} ->
        Logger.warning("[Bolt] Cannot bind port #{port}: #{inspect(reason)} — bolt listener disabled")
        {:ok, %{socket: nil, port: port, transport: :disabled}}
    end
  end

  @impl true
  def handle_call(:transport, _from, %{transport: t} = state),
    do: {:reply, {:ok, t}, state}

  # Raw UDP: :gen_udp delivers {udp, socket, ip, port, data}
  @impl true
  def handle_info({:udp, _socket, src_ip, _src_port, data}, state) do
    handle_packet(data, format_ip(src_ip))
    {:noreply, state}
  end

  # QUIC datagram (quicer delivers {:quic, :datagram, _conn, data})
  def handle_info({:quic, :datagram, _conn, data}, state) do
    handle_packet(data, "quic")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp handle_packet(data, src) do
    case Packet.decode(data) do
      {:ok, packet} ->
        Logger.debug("[Bolt] Received bolt from #{src}")
        Notify.incoming(packet, src)

      {:error, :bad_magic} ->
        # Could be a WoL packet — ignore silently
        :ok

      {:error, reason} ->
        Logger.debug("[Bolt] Ignored malformed packet from #{src}: #{reason}")
    end
  end

  defp open_socket(port) do
    udp_opts = [:binary, active: true, reuseaddr: true]

    case :gen_udp.open(port, udp_opts) do
      {:ok, socket} -> {:ok, socket, :udp}
      {:error, _} = err -> err
    end
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip({a, b, c, d, e, f, g, h}),
    do: Enum.map_join([a, b, c, d, e, f, g, h], ":", &Integer.to_string(&1, 16))
  defp format_ip(other), do: inspect(other)
end

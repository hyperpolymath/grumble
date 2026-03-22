# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Burble.Transport.QUIC do
  @moduledoc """
  QUIC transport layer for Burble voice connections.

  Wraps the `quicer` NIF library (Erlang binding to msquic) to provide
  QUIC-based transport as a superior alternative to WebSocket for voice
  signaling and media. QUIC offers several advantages for real-time voice:

  ## Why QUIC for voice?

  - **0-RTT reconnection**: Participants who drop and reconnect (e.g., mobile
    network switch) can resume with zero round-trip overhead, avoiding the
    audible gap that TCP+TLS handshakes cause.

  - **Multiplexed streams**: Voice datagrams, signaling messages, and text
    chat each get their own stream with independent flow control. A large
    text message won't block voice data (head-of-line blocking avoidance).

  - **Connection migration**: When a client's IP changes (Wi-Fi → cellular),
    the QUIC connection ID persists — no reconnect needed. Critical for
    mobile gaming (IDApTIK) where players move between networks.

  - **Unreliable datagrams** (RFC 9221): Voice frames are sent as QUIC
    datagrams — no retransmission, no ordering, minimal latency. Lost
    frames are handled by the jitter buffer and PLC in the I/O kernel.

  ## Stream multiplexing

  Each client connection carries three logical channels:

  | Stream ID | Type       | Reliability | Purpose                           |
  |-----------|------------|-------------|-----------------------------------|
  | 0         | Datagram   | Unreliable  | Opus voice frames (20ms packets)  |
  | 1         | Bidi       | Reliable    | Signaling (Bebop-encoded)         |
  | 2         | Bidi       | Reliable    | Text chat (NNTPS-threaded)        |

  ## Fallback

  When QUIC is unavailable (corporate firewalls blocking UDP, missing quicer
  NIF, client browser without WebTransport), the module signals the caller
  to fall back to `BurbleWeb.VoiceSocket` (Phoenix WebSocket channel).

  ## OTP supervision

  Each QUIC listener is a GenServer under `Burble.Transport.Supervisor`.
  Per-connection state is managed as a map inside the GenServer (connections
  are lightweight — msquic handles the heavy lifting in C).

  ## Configuration

  Set in `config/runtime.exs`:

      config :burble, Burble.Transport.QUIC,
        port: 6474,
        certfile: "priv/cert/selfsigned.pem",
        keyfile: "priv/cert/selfsigned_key.pem",
        alpn: ["burble-voice-v1"],
        max_connections: 10_000,
        idle_timeout_ms: 30_000
  """

  use GenServer
  require Logger

  # ---------------------------------------------------------------------------
  # Type definitions
  # ---------------------------------------------------------------------------

  @typedoc "Opaque QUIC connection handle from quicer."
  @type conn_handle :: reference()

  @typedoc "Opaque QUIC stream handle from quicer."
  @type stream_handle :: reference()

  @typedoc """
  Per-connection state tracking the three multiplexed streams.

  - `:conn` — the quicer connection handle.
  - `:voice_stream` — unreliable datagram pseudo-stream for Opus frames.
  - `:signal_stream` — reliable bidirectional stream for Bebop signaling.
  - `:text_stream` — reliable bidirectional stream for text chat.
  - `:user_id` — authenticated user ID (set after signaling handshake).
  - `:room_id` — current room (set after Join message).
  - `:zero_rtt` — whether this connection used 0-RTT resumption.
  - `:migrated_from` — previous IP if connection migration occurred.
  """
  @type connection_state :: %{
          conn: conn_handle(),
          voice_stream: stream_handle() | nil,
          signal_stream: stream_handle() | nil,
          text_stream: stream_handle() | nil,
          user_id: String.t() | nil,
          room_id: String.t() | nil,
          zero_rtt: boolean(),
          migrated_from: :inet.ip_address() | nil
        }

  @typedoc "GenServer state: listener handle + map of connection ID → connection_state."
  @type state :: %{
          listener: reference() | nil,
          connections: %{reference() => connection_state()},
          config: keyword()
        }

  # ---------------------------------------------------------------------------
  # Default configuration
  # ---------------------------------------------------------------------------

  # QUIC listens on the next port after the HTTP server (6473 + 1).
  @default_port 6474

  # ALPN protocol identifier — clients must match this to connect.
  @default_alpn ["burble-voice-v1"]

  # Maximum concurrent QUIC connections per listener.
  @default_max_connections 10_000

  # Idle timeout before the server closes a silent connection (30s).
  @default_idle_timeout_ms 30_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Start the QUIC transport listener under the given supervisor.

  Options are read from application config under `:burble, Burble.Transport.QUIC`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Send an unreliable voice datagram to a connected participant.

  Uses QUIC datagrams (RFC 9221) — no retransmission, no ordering.
  Returns `:ok` on success, `{:error, reason}` if the connection is
  gone or datagrams are not supported.
  """
  @spec send_voice_datagram(conn_handle(), binary()) :: :ok | {:error, term()}
  def send_voice_datagram(conn, data) do
    GenServer.call(__MODULE__, {:send_datagram, conn, data})
  end

  @doc """
  Send a reliable signaling message (Bebop-encoded) to a participant.

  Uses the reliable bidirectional signaling stream (stream 1).
  """
  @spec send_signal(conn_handle(), binary()) :: :ok | {:error, term()}
  def send_signal(conn, data) do
    GenServer.call(__MODULE__, {:send_signal, conn, data})
  end

  @doc """
  Send a reliable text chat message to a participant.

  Uses the reliable bidirectional text stream (stream 2).
  """
  @spec send_text(conn_handle(), binary()) :: :ok | {:error, term()}
  def send_text(conn, data) do
    GenServer.call(__MODULE__, {:send_text, conn, data})
  end

  @doc """
  Check whether the quicer NIF is available on this system.

  Returns `true` if `quicer` is loaded and functional, `false` otherwise.
  When `false`, callers should fall back to WebSocket transport.
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(:quicer) and function_exported?(:quicer, :listen, 2)
  end

  @doc """
  Get the count of active QUIC connections.
  """
  @spec connection_count() :: non_neg_integer()
  def connection_count do
    GenServer.call(__MODULE__, :connection_count)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    # Merge provided opts with application config and defaults.
    app_config = Application.get_env(:burble, __MODULE__, [])
    config = Keyword.merge(default_config(), Keyword.merge(app_config, opts))

    state = %{
      listener: nil,
      connections: %{},
      config: config
    }

    # Attempt to start the QUIC listener. If quicer is not available,
    # log a warning and remain in a dormant state (WebSocket fallback).
    case start_listener(config) do
      {:ok, listener} ->
        Logger.info(
          "[Burble.Transport.QUIC] Listener started on port #{config[:port]} " <>
            "(ALPN: #{inspect(config[:alpn])})"
        )

        {:ok, %{state | listener: listener}}

      {:error, :quicer_not_available} ->
        Logger.warning(
          "[Burble.Transport.QUIC] quicer NIF not available — " <>
            "QUIC transport disabled, falling back to WebSocket"
        )

        {:ok, state}

      {:error, reason} ->
        Logger.error(
          "[Burble.Transport.QUIC] Failed to start listener: #{inspect(reason)}"
        )

        # Don't crash the supervision tree — degrade gracefully.
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:send_datagram, conn, data}, _from, state) do
    # Send an unreliable QUIC datagram (RFC 9221) for voice frames.
    # These are fire-and-forget — lost packets are handled by the
    # jitter buffer and packet loss concealment in the I/O kernel.
    result =
      if available?() do
        try do
          :quicer.send_dgram(conn, data)
        rescue
          e -> {:error, {:send_failed, e}}
        end
      else
        {:error, :quicer_not_available}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:send_signal, conn, data}, _from, state) do
    # Send on the reliable signaling stream (Bebop-encoded messages).
    result = send_on_stream(state, conn, :signal_stream, data)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:send_text, conn, data}, _from, state) do
    # Send on the reliable text chat stream.
    result = send_on_stream(state, conn, :text_stream, data)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:connection_count, _from, state) do
    {:reply, map_size(state.connections), state}
  end

  @impl true
  def handle_info({:quic, :new_conn, conn, info}, state) do
    # A new QUIC connection has been accepted by the listener.
    # Check for 0-RTT resumption (session ticket reuse).
    zero_rtt = Map.get(info, :is_resumed, false)

    if zero_rtt do
      Logger.debug("[Burble.Transport.QUIC] 0-RTT reconnection from #{format_peer(info)}")
    else
      Logger.debug("[Burble.Transport.QUIC] New connection from #{format_peer(info)}")
    end

    # Initialize per-connection state. Streams are registered as they open.
    conn_state = %{
      conn: conn,
      voice_stream: nil,
      signal_stream: nil,
      text_stream: nil,
      user_id: nil,
      room_id: nil,
      zero_rtt: zero_rtt,
      migrated_from: nil
    }

    # Accept the connection (handshake completes asynchronously).
    if available?(), do: :quicer.handshake(conn)

    {:noreply, put_in(state, [:connections, conn], conn_state)}
  end

  @impl true
  def handle_info({:quic, :connected, conn, _info}, state) do
    # QUIC handshake completed — connection is fully established.
    Logger.debug("[Burble.Transport.QUIC] Connection established: #{inspect(conn)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:quic, :new_stream, stream, %{stream_id: stream_id} = _info}, state) do
    # A new stream has been opened on an existing connection.
    # Map stream IDs to our three logical channels.
    conn = find_conn_for_stream(state, stream)

    if conn do
      stream_type = classify_stream(stream_id)

      Logger.debug(
        "[Burble.Transport.QUIC] Stream opened: #{stream_type} (ID: #{stream_id})"
      )

      updated =
        update_in(state, [:connections, conn], fn conn_state ->
          Map.put(conn_state, stream_type, stream)
        end)

      {:noreply, updated}
    else
      Logger.warning("[Burble.Transport.QUIC] Stream on unknown connection, ignoring")
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:quic, :dgram, conn, data}, state) do
    # Received an unreliable QUIC datagram — this is a voice frame.
    # Route it to the Media.Engine for SFU distribution.
    conn_state = Map.get(state.connections, conn)

    if conn_state && conn_state.room_id do
      # Forward the voice datagram to the media engine for SFU fanout.
      Burble.Media.Engine.handle_voice_datagram(
        conn_state.room_id,
        conn_state.user_id,
        data
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:quic, :recv, stream, data}, state) do
    # Received data on a reliable stream — either signaling or text.
    conn = find_conn_for_stream(state, stream)
    conn_state = conn && Map.get(state.connections, conn)

    cond do
      conn_state && conn_state.signal_stream == stream ->
        # Signaling message — decode Bebop and dispatch.
        handle_signal_data(conn, conn_state, data, state)

      conn_state && conn_state.text_stream == stream ->
        # Text chat message — forward to the room's text channel.
        handle_text_data(conn, conn_state, data, state)

      true ->
        Logger.warning("[Burble.Transport.QUIC] Data on unknown stream, dropping")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:quic, :conn_closed, conn, reason}, state) do
    # Connection closed — clean up state and notify the room.
    conn_state = Map.get(state.connections, conn)

    if conn_state && conn_state.room_id do
      Logger.info(
        "[Burble.Transport.QUIC] Connection closed for user #{conn_state.user_id} " <>
          "in room #{conn_state.room_id} (reason: #{inspect(reason)})"
      )

      # Notify the room that this participant's transport is gone.
      Burble.Room.handle_transport_disconnect(conn_state.room_id, conn_state.user_id)
    end

    {:noreply, %{state | connections: Map.delete(state.connections, conn)}}
  end

  @impl true
  def handle_info({:quic, :conn_migrated, conn, %{new_addr: new_addr, old_addr: old_addr}}, state) do
    # Connection migration — the client's IP changed but the QUIC
    # connection ID persists. Log for diagnostics and update state.
    Logger.info(
      "[Burble.Transport.QUIC] Connection migrated: #{format_addr(old_addr)} → #{format_addr(new_addr)}"
    )

    updated =
      update_in(state, [:connections, conn], fn conn_state ->
        %{conn_state | migrated_from: old_addr}
      end)

    {:noreply, updated}
  end

  @impl true
  def handle_info(msg, state) do
    # Catch-all for unexpected messages — log but don't crash.
    Logger.debug("[Burble.Transport.QUIC] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Build default configuration keyword list.
  @spec default_config() :: keyword()
  defp default_config do
    [
      port: @default_port,
      alpn: @default_alpn,
      max_connections: @default_max_connections,
      idle_timeout_ms: @default_idle_timeout_ms,
      certfile: "priv/cert/selfsigned.pem",
      keyfile: "priv/cert/selfsigned_key.pem"
    ]
  end

  # Attempt to start the quicer listener with the given configuration.
  # Returns {:ok, listener} or {:error, reason}.
  @spec start_listener(keyword()) :: {:ok, reference()} | {:error, term()}
  defp start_listener(config) do
    unless available?() do
      {:error, :quicer_not_available}
    else
      listen_opts = [
        certfile: config[:certfile],
        keyfile: config[:keyfile],
        alpn: config[:alpn],
        idle_timeout_ms: config[:idle_timeout_ms],
        peer_unidi_stream_count: 0,
        peer_bidi_stream_count: 3,
        datagram_receive_enabled: true,
        max_connections: config[:max_connections],
        # Enable 0-RTT for fast reconnection (session tickets).
        server_resumption_level: 2
      ]

      :quicer.listen(config[:port], listen_opts)
    end
  end

  # Send data on a named stream (:signal_stream or :text_stream) for a connection.
  @spec send_on_stream(state(), conn_handle(), atom(), binary()) :: :ok | {:error, term()}
  defp send_on_stream(state, conn, stream_key, data) do
    case get_in(state, [:connections, conn, stream_key]) do
      nil ->
        {:error, :stream_not_open}

      stream ->
        if available?() do
          try do
            :quicer.send(stream, data)
          rescue
            e -> {:error, {:send_failed, e}}
          end
        else
          {:error, :quicer_not_available}
        end
    end
  end

  # Classify a QUIC stream ID into one of our three logical channels.
  # Stream IDs follow the QUIC convention: client-initiated bidi streams
  # are 0, 4, 8, ... — we use the first two for signaling and text.
  @spec classify_stream(non_neg_integer()) :: :signal_stream | :text_stream | :voice_stream
  defp classify_stream(stream_id) do
    case rem(div(stream_id, 4), 3) do
      0 -> :signal_stream
      1 -> :text_stream
      _ -> :voice_stream
    end
  end

  # Find the connection handle that owns a given stream handle.
  @spec find_conn_for_stream(state(), stream_handle()) :: conn_handle() | nil
  defp find_conn_for_stream(state, stream) do
    Enum.find_value(state.connections, fn {conn, conn_state} ->
      if stream in [conn_state.signal_stream, conn_state.text_stream, conn_state.voice_stream] do
        conn
      end
    end)
  end

  # Handle incoming signaling data (Bebop-encoded voice_signal messages).
  # Decodes and dispatches to the appropriate room/media handler.
  @spec handle_signal_data(conn_handle(), connection_state(), binary(), state()) ::
          {:noreply, state()}
  defp handle_signal_data(conn, conn_state, data, state) do
    # TODO: Decode Bebop VoiceSignal union and dispatch.
    # For now, forward raw bytes to the signaling handler.
    Logger.debug(
      "[Burble.Transport.QUIC] Signal data (#{byte_size(data)} bytes) " <>
        "from user #{conn_state.user_id}"
    )

    {:noreply, state}
  end

  # Handle incoming text chat data on the reliable text stream.
  @spec handle_text_data(conn_handle(), connection_state(), binary(), state()) ::
          {:noreply, state()}
  defp handle_text_data(conn, conn_state, data, state) do
    Logger.debug(
      "[Burble.Transport.QUIC] Text data (#{byte_size(data)} bytes) " <>
        "from user #{conn_state.user_id}"
    )

    {:noreply, state}
  end

  # Format a peer address from quicer connection info for logging.
  @spec format_peer(map()) :: String.t()
  defp format_peer(info) do
    case Map.get(info, :peer) do
      {ip, port} -> "#{format_addr(ip)}:#{port}"
      _ -> "unknown"
    end
  end

  # Format an IP address tuple as a human-readable string.
  @spec format_addr(:inet.ip_address()) :: String.t()
  defp format_addr({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp format_addr({a, b, c, d, e, f, g, h}),
    do: Enum.map_join([a, b, c, d, e, f, g, h], ":", &Integer.to_string(&1, 16))

  defp format_addr(other), do: inspect(other)
end

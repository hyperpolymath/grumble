# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Burble.Transport.RTSP do
  @moduledoc """
  RTSP transport module for Burble broadcast rooms and screen share.

  Implements a lightweight RTSP server for one-to-many media distribution.
  While Burble's standard voice channels use WebRTC via the SFU (and
  optionally QUIC datagrams), broadcast scenarios require a different
  topology:

  ## Use cases

  - **Stage rooms**: A speaker broadcasts to hundreds of listeners. The SFU
    forwards a single RTP stream to this module, which redistributes via
    RTSP to all viewers — avoiding N PeerConnections for N listeners.

  - **Screen share**: A participant shares their screen as an RTP video
    stream. This module accepts the RTP input and serves it as an RTSP
    mountpoint that viewers can subscribe to.

  - **IDApTIK Q character CCTV feeds**: In IDApTIK's asymmetric co-op mode,
    Q monitors the facility via CCTV cameras. Each camera feed is an RTSP
    mountpoint that Q's PanLL workspace can display in real-time. Jessica
    never sees Q's view (asymmetric design), but Q can watch multiple
    camera feeds simultaneously and relay intel via spatial voice.

  ## Architecture

  ```
  Producer (speaker/screen/CCTV)
      │
      ▼ RTP stream
  ┌─────────────────────┐
  │ Burble.Transport.RTSP │
  │   ├─ Mountpoint A    │  ← /live/room-{id}/speaker
  │   ├─ Mountpoint B    │  ← /live/room-{id}/screen
  │   └─ Mountpoint C    │  ← /live/idaptik/{level}/cctv/{cam}
  └─────────────────────┘
      │ RTSP/RTP
      ▼ (multicast or unicast)
  [Viewer 1] [Viewer 2] ... [Viewer N]
  ```

  ## Protocol details

  - RTSP control: TCP port 8554 (configurable).
  - RTP media: UDP, dynamically allocated port pairs.
  - Codec: Opus for audio, VP8/VP9/H.264 for video (passthrough — no transcoding).
  - SDP: Generated per-mountpoint based on the producer's codec negotiation.

  ## OTP design

  This module is a GenServer that manages a registry of active mountpoints.
  Each mountpoint tracks its producer (the RTP source) and a set of
  subscribers (RTSP clients). RTP packets from the producer are fanned out
  to all subscribers with minimal copying (binary reference sharing).

  ## Configuration

  Set in `config/runtime.exs`:

      config :burble, Burble.Transport.RTSP,
        port: 8554,
        max_mountpoints: 500,
        max_subscribers_per_mount: 5000,
        rtp_port_range: {20000, 30000}
  """

  use GenServer
  require Logger

  # ---------------------------------------------------------------------------
  # Type definitions
  # ---------------------------------------------------------------------------

  @typedoc """
  A mountpoint path, e.g., "/live/room-abc123/speaker" or
  "/live/idaptik/level-7/cctv/cam-north".
  """
  @type mountpoint_path :: String.t()

  @typedoc """
  State of a single RTSP mountpoint.

  - `:path` — the RTSP URL path for this mountpoint.
  - `:producer` — the process or socket producing RTP packets.
  - `:subscribers` — set of subscriber pids receiving RTP fanout.
  - `:sdp` — SDP description generated from the producer's codec.
  - `:room_id` — Burble room this mountpoint belongs to.
  - `:created_at` — when the mountpoint was registered.
  - `:packet_count` — running count of RTP packets distributed.
  """
  @type mountpoint :: %{
          path: mountpoint_path(),
          producer: pid() | nil,
          subscribers: MapSet.t(pid()),
          sdp: String.t() | nil,
          room_id: String.t(),
          created_at: DateTime.t(),
          packet_count: non_neg_integer()
        }

  @typedoc "GenServer state: listener socket + mountpoint registry."
  @type state :: %{
          listener: :gen_tcp.socket() | nil,
          mountpoints: %{mountpoint_path() => mountpoint()},
          rtp_sockets: %{mountpoint_path() => :gen_udp.socket()},
          config: keyword()
        }

  # ---------------------------------------------------------------------------
  # Default configuration
  # ---------------------------------------------------------------------------

  # Standard RTSP port (RFC 7826).
  @default_port 8554

  # Maximum concurrent mountpoints (one per broadcast/screen share).
  @default_max_mountpoints 500

  # Maximum subscribers per mountpoint (large broadcast rooms).
  @default_max_subscribers 5000

  # UDP port range for RTP media streams.
  @default_rtp_port_range {20_000, 30_000}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Start the RTSP transport server under the supervision tree.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new RTSP mountpoint for a broadcast room or screen share.

  Returns `{:ok, mountpoint_path}` on success. The mountpoint becomes
  available for RTSP DESCRIBE/SETUP/PLAY requests from viewers.

  ## Parameters

  - `room_id` — the Burble room UUID this mountpoint belongs to.
  - `stream_type` — `:speaker`, `:screen`, or `:cctv`.
  - `opts` — optional keyword list:
    - `:camera_id` — required for `:cctv` type (e.g., "cam-north").
    - `:level_id` — required for `:cctv` type (IDApTIK level identifier).
    - `:codec` — audio/video codec hint for SDP generation.
  """
  @spec register_mountpoint(String.t(), atom(), keyword()) ::
          {:ok, mountpoint_path()} | {:error, term()}
  def register_mountpoint(room_id, stream_type, opts \\ []) do
    GenServer.call(__MODULE__, {:register_mountpoint, room_id, stream_type, opts})
  end

  @doc """
  Remove a mountpoint and disconnect all subscribers.

  Called when a broadcast ends, screen share stops, or CCTV feed is
  deactivated. All connected RTSP clients receive a TEARDOWN.
  """
  @spec remove_mountpoint(mountpoint_path()) :: :ok | {:error, :not_found}
  def remove_mountpoint(path) do
    GenServer.call(__MODULE__, {:remove_mountpoint, path})
  end

  @doc """
  Inject an RTP packet into a mountpoint for fanout to subscribers.

  Called by the SFU or the producer's RTP receive loop. The packet is
  forwarded to all subscribers with minimal copying (Erlang binary
  reference counting ensures the packet bytes are shared, not duplicated).

  ## Parameters

  - `path` — the mountpoint path.
  - `packet` — raw RTP packet binary.
  """
  @spec inject_rtp(mountpoint_path(), binary()) :: :ok | {:error, :not_found}
  def inject_rtp(path, packet) do
    GenServer.cast(__MODULE__, {:inject_rtp, path, packet})
  end

  @doc """
  Subscribe a process to receive RTP packets from a mountpoint.

  The subscriber process will receive `{:rtsp_rtp, path, packet}` messages
  for each RTP packet distributed on this mountpoint.
  """
  @spec subscribe(mountpoint_path(), pid()) :: :ok | {:error, term()}
  def subscribe(path, subscriber_pid) do
    GenServer.call(__MODULE__, {:subscribe, path, subscriber_pid})
  end

  @doc """
  Unsubscribe a process from a mountpoint.
  """
  @spec unsubscribe(mountpoint_path(), pid()) :: :ok
  def unsubscribe(path, subscriber_pid) do
    GenServer.call(__MODULE__, {:unsubscribe, path, subscriber_pid})
  end

  @doc """
  List all active mountpoints with their subscriber counts.

  Returns a list of `{path, subscriber_count, packet_count}` tuples.
  """
  @spec list_mountpoints() :: [{mountpoint_path(), non_neg_integer(), non_neg_integer()}]
  def list_mountpoints do
    GenServer.call(__MODULE__, :list_mountpoints)
  end

  @doc """
  Get the SDP description for a mountpoint (used in RTSP DESCRIBE response).
  """
  @spec get_sdp(mountpoint_path()) :: {:ok, String.t()} | {:error, :not_found}
  def get_sdp(path) do
    GenServer.call(__MODULE__, {:get_sdp, path})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    # Merge opts with application config and defaults.
    app_config = Application.get_env(:burble, __MODULE__, [])
    config = Keyword.merge(default_config(), Keyword.merge(app_config, opts))

    state = %{
      listener: nil,
      mountpoints: %{},
      rtp_sockets: %{},
      config: config
    }

    # Start the RTSP TCP listener for control connections.
    case start_rtsp_listener(config[:port]) do
      {:ok, listener} ->
        Logger.info(
          "[Burble.Transport.RTSP] RTSP server listening on port #{config[:port]}"
        )

        # Spawn the acceptor loop to handle incoming RTSP connections.
        spawn_acceptor(listener)
        {:ok, %{state | listener: listener}}

      {:error, reason} ->
        Logger.error(
          "[Burble.Transport.RTSP] Failed to start RTSP listener: #{inspect(reason)} — " <>
            "broadcast/screen share will be unavailable"
        )

        # Degrade gracefully — broadcast features are optional.
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:register_mountpoint, room_id, stream_type, opts}, _from, state) do
    # Build the mountpoint path from room ID and stream type.
    path = build_mountpoint_path(room_id, stream_type, opts)

    if map_size(state.mountpoints) >= state.config[:max_mountpoints] do
      {:reply, {:error, :max_mountpoints_reached}, state}
    else
      mount = %{
        path: path,
        producer: nil,
        subscribers: MapSet.new(),
        sdp: generate_sdp(path, stream_type, opts),
        room_id: room_id,
        created_at: DateTime.utc_now(),
        packet_count: 0
      }

      Logger.info("[Burble.Transport.RTSP] Registered mountpoint: #{path}")

      updated = put_in(state, [:mountpoints, path], mount)
      {:reply, {:ok, path}, updated}
    end
  end

  @impl true
  def handle_call({:remove_mountpoint, path}, _from, state) do
    case Map.pop(state.mountpoints, path) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {mount, remaining} ->
        # Notify all subscribers that the mountpoint is going away.
        for sub <- mount.subscribers do
          send(sub, {:rtsp_teardown, path})
        end

        # Close the RTP socket if one was allocated.
        case Map.pop(state.rtp_sockets, path) do
          {nil, _} -> :ok
          {socket, _} -> :gen_udp.close(socket)
        end

        Logger.info(
          "[Burble.Transport.RTSP] Removed mountpoint: #{path} " <>
            "(#{MapSet.size(mount.subscribers)} subscribers disconnected)"
        )

        {:reply, :ok,
         %{state | mountpoints: remaining, rtp_sockets: Map.delete(state.rtp_sockets, path)}}
    end
  end

  @impl true
  def handle_call({:subscribe, path, pid}, _from, state) do
    case Map.get(state.mountpoints, path) do
      nil ->
        {:reply, {:error, :not_found}, state}

      mount ->
        if MapSet.size(mount.subscribers) >= state.config[:max_subscribers_per_mount] do
          {:reply, {:error, :max_subscribers_reached}, state}
        else
          # Monitor the subscriber so we can clean up if it dies.
          Process.monitor(pid)
          updated = put_in(state, [:mountpoints, path, :subscribers], MapSet.put(mount.subscribers, pid))

          Logger.debug(
            "[Burble.Transport.RTSP] Subscriber added to #{path} " <>
              "(total: #{MapSet.size(mount.subscribers) + 1})"
          )

          {:reply, :ok, updated}
        end
    end
  end

  @impl true
  def handle_call({:unsubscribe, path, pid}, _from, state) do
    updated =
      update_in(state, [:mountpoints, path, :subscribers], fn
        nil -> MapSet.new()
        subs -> MapSet.delete(subs, pid)
      end)

    {:reply, :ok, updated}
  end

  @impl true
  def handle_call(:list_mountpoints, _from, state) do
    listing =
      Enum.map(state.mountpoints, fn {path, mount} ->
        {path, MapSet.size(mount.subscribers), mount.packet_count}
      end)

    {:reply, listing, state}
  end

  @impl true
  def handle_call({:get_sdp, path}, _from, state) do
    case Map.get(state.mountpoints, path) do
      nil -> {:reply, {:error, :not_found}, state}
      mount -> {:reply, {:ok, mount.sdp}, state}
    end
  end

  @impl true
  def handle_cast({:inject_rtp, path, packet}, state) do
    case Map.get(state.mountpoints, path) do
      nil ->
        {:noreply, state}

      mount ->
        # Fan out the RTP packet to all subscribers.
        # Erlang's binary reference counting means we share the packet
        # bytes across all send operations — no per-subscriber copy.
        for sub <- mount.subscribers do
          send(sub, {:rtsp_rtp, path, packet})
        end

        # Increment the packet counter for diagnostics.
        updated =
          update_in(state, [:mountpoints, path, :packet_count], &(&1 + 1))

        {:noreply, updated}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # A subscriber process died — remove it from all mountpoints.
    updated =
      update_in(state, [:mountpoints], fn mounts ->
        Map.new(mounts, fn {path, mount} ->
          {path, %{mount | subscribers: MapSet.delete(mount.subscribers, pid)}}
        end)
      end)

    {:noreply, updated}
  end

  @impl true
  def handle_info({:rtsp_connection, client_socket}, state) do
    # A new RTSP client has connected. Spawn a handler process for the
    # RTSP control session (DESCRIBE → SETUP → PLAY lifecycle).
    spawn(fn -> handle_rtsp_session(client_socket, state) end)

    # Continue accepting connections.
    if state.listener, do: spawn_acceptor(state.listener)

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[Burble.Transport.RTSP] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Build default configuration.
  @spec default_config() :: keyword()
  defp default_config do
    [
      port: @default_port,
      max_mountpoints: @default_max_mountpoints,
      max_subscribers_per_mount: @default_max_subscribers,
      rtp_port_range: @default_rtp_port_range
    ]
  end

  # Start the TCP listener for RTSP control connections.
  @spec start_rtsp_listener(non_neg_integer()) :: {:ok, :gen_tcp.socket()} | {:error, term()}
  defp start_rtsp_listener(port) do
    :gen_tcp.listen(port, [
      :binary,
      {:active, false},
      {:reuseaddr, true},
      {:packet, :line}
    ])
  end

  # Spawn an asynchronous acceptor that waits for the next RTSP client.
  @spec spawn_acceptor(:gen_tcp.socket()) :: pid()
  defp spawn_acceptor(listener) do
    server = self()

    spawn(fn ->
      case :gen_tcp.accept(listener) do
        {:ok, client} ->
          send(server, {:rtsp_connection, client})

        {:error, reason} ->
          Logger.warning("[Burble.Transport.RTSP] Accept failed: #{inspect(reason)}")
      end
    end)
  end

  # Build a mountpoint path from room ID and stream type.
  #
  # Examples:
  #   - Speaker: /live/room-abc123/speaker
  #   - Screen:  /live/room-abc123/screen
  #   - CCTV:    /live/idaptik/level-7/cctv/cam-north
  @spec build_mountpoint_path(String.t(), atom(), keyword()) :: mountpoint_path()
  defp build_mountpoint_path(room_id, :speaker, _opts), do: "/live/room-#{room_id}/speaker"
  defp build_mountpoint_path(room_id, :screen, _opts), do: "/live/room-#{room_id}/screen"

  defp build_mountpoint_path(_room_id, :cctv, opts) do
    level_id = Keyword.fetch!(opts, :level_id)
    camera_id = Keyword.fetch!(opts, :camera_id)
    "/live/idaptik/#{level_id}/cctv/#{camera_id}"
  end

  defp build_mountpoint_path(room_id, type, _opts), do: "/live/room-#{room_id}/#{type}"

  # Generate a minimal SDP description for a mountpoint.
  # This is used in RTSP DESCRIBE responses so clients know what codec
  # to expect before issuing SETUP.
  @spec generate_sdp(mountpoint_path(), atom(), keyword()) :: String.t()
  defp generate_sdp(path, stream_type, opts) do
    codec = Keyword.get(opts, :codec, :opus)

    # Build SDP based on stream type and codec.
    media_line =
      case {stream_type, codec} do
        {:speaker, :opus} -> "m=audio 0 RTP/AVP 111\r\na=rtpmap:111 opus/48000/2"
        {:screen, :vp8} -> "m=video 0 RTP/AVP 96\r\na=rtpmap:96 VP8/90000"
        {:screen, :h264} -> "m=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000"
        {:cctv, _} -> "m=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000"
        {_, :opus} -> "m=audio 0 RTP/AVP 111\r\na=rtpmap:111 opus/48000/2"
        _ -> "m=audio 0 RTP/AVP 111\r\na=rtpmap:111 opus/48000/2"
      end

    """
    v=0\r
    o=burble 0 0 IN IP4 0.0.0.0\r
    s=#{path}\r
    c=IN IP4 0.0.0.0\r
    t=0 0\r
    #{media_line}\r
    a=control:#{path}\r
    """
  end

  # Handle a single RTSP control session (one TCP connection from a viewer).
  # Implements the minimal RTSP method set: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN.
  @spec handle_rtsp_session(:gen_tcp.socket(), state()) :: :ok
  defp handle_rtsp_session(client, _state) do
    case :gen_tcp.recv(client, 0, 30_000) do
      {:ok, line} ->
        # Parse the RTSP request line (e.g., "DESCRIBE rtsp://host/path RTSP/1.0").
        case parse_rtsp_request(line) do
          {:ok, method, path, _version} ->
            handle_rtsp_method(client, method, path)
            # Continue reading requests on this session.
            handle_rtsp_session(client, _state)

          {:error, _} ->
            Logger.debug("[Burble.Transport.RTSP] Malformed RTSP request, closing")
            :gen_tcp.close(client)
        end

      {:error, :timeout} ->
        Logger.debug("[Burble.Transport.RTSP] RTSP session timed out")
        :gen_tcp.close(client)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Burble.Transport.RTSP] RTSP recv error: #{inspect(reason)}")
        :gen_tcp.close(client)
    end
  end

  # Parse an RTSP request line into {method, path, version}.
  @spec parse_rtsp_request(String.t()) :: {:ok, String.t(), String.t(), String.t()} | {:error, :malformed}
  defp parse_rtsp_request(line) do
    case String.split(String.trim(line), " ", parts: 3) do
      [method, uri, version] ->
        # Extract the path from the RTSP URI (strip scheme + host).
        path = URI.parse(uri) |> Map.get(:path, uri)
        {:ok, method, path, version}

      _ ->
        {:error, :malformed}
    end
  end

  # Dispatch RTSP methods. This is a minimal implementation — production
  # would need full header parsing, session tracking, and RTP interleaving.
  @spec handle_rtsp_method(:gen_tcp.socket(), String.t(), String.t()) :: :ok
  defp handle_rtsp_method(client, "OPTIONS", _path) do
    response =
      "RTSP/1.0 200 OK\r\n" <>
        "Public: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN\r\n" <>
        "\r\n"

    :gen_tcp.send(client, response)
  end

  defp handle_rtsp_method(client, "DESCRIBE", path) do
    case get_sdp(path) do
      {:ok, sdp} ->
        response =
          "RTSP/1.0 200 OK\r\n" <>
            "Content-Type: application/sdp\r\n" <>
            "Content-Length: #{byte_size(sdp)}\r\n" <>
            "\r\n" <>
            sdp

        :gen_tcp.send(client, response)

      {:error, :not_found} ->
        :gen_tcp.send(client, "RTSP/1.0 404 Not Found\r\n\r\n")
    end
  end

  defp handle_rtsp_method(client, "SETUP", _path) do
    # Minimal SETUP response — production would allocate RTP ports and
    # create a transport session.
    response =
      "RTSP/1.0 200 OK\r\n" <>
        "Transport: RTP/AVP;unicast\r\n" <>
        "Session: burble-rtsp-session\r\n" <>
        "\r\n"

    :gen_tcp.send(client, response)
  end

  defp handle_rtsp_method(client, "PLAY", path) do
    # Subscribe the caller to the mountpoint's RTP stream.
    # In production, this would wire the subscriber PID to
    # receive {:rtsp_rtp, ...} messages and relay them via RTP/UDP.
    response =
      "RTSP/1.0 200 OK\r\n" <>
        "Session: burble-rtsp-session\r\n" <>
        "\r\n"

    :gen_tcp.send(client, response)
  end

  defp handle_rtsp_method(client, "TEARDOWN", _path) do
    :gen_tcp.send(client, "RTSP/1.0 200 OK\r\n\r\n")
    :gen_tcp.close(client)
  end

  defp handle_rtsp_method(client, method, _path) do
    Logger.debug("[Burble.Transport.RTSP] Unsupported RTSP method: #{method}")
    :gen_tcp.send(client, "RTSP/1.0 405 Method Not Allowed\r\n\r\n")
  end
end

# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule BurbleWeb.API.RoomController do
  use Phoenix.Controller, formats: [:json]

  alias Burble.Rooms.{Room, RoomManager}

  def index(conn, %{"server_id" => _server_id}) do
    rooms = RoomManager.list_active_rooms()
    |> Enum.map(fn room_id ->
      case Room.get_state(room_id) do
        {:ok, state} -> state
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)

    json(conn, %{rooms: rooms})
  end

  def create(conn, %{"server_id" => server_id} = params) do
    room_id = Map.get(params, "room_id", generate_uuid())
    name = Map.get(params, "name", "New Room")

    case RoomManager.start_room(room_id, server_id: server_id, name: name) do
      {:ok, _pid} -> json(conn, %{room_id: room_id, name: name})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: inspect(reason)})
    end
  end

  def show(conn, %{"id" => room_id}) do
    case Room.get_state(room_id) do
      {:ok, state} -> json(conn, state)
      {:error, _} -> conn |> put_status(404) |> json(%{error: "room_not_found"})
    end
  end

  def participants(conn, %{"id" => room_id}) do
    case Room.get_state(room_id) do
      {:ok, %{participants: p}} -> json(conn, %{participants: p})
      {:error, _} -> conn |> put_status(404) |> json(%{error: "room_not_found"})
    end
  end

  # Generate a v4 UUID without Ecto dependency.
  defp generate_uuid do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)
    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> String.replace(~r/(.{8})(.{4})(.{4})(.{4})(.{12})/, "\\1-\\2-\\3-\\4-\\5")
  end
end

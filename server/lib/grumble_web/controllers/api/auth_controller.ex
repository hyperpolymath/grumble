# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule BurbleWeb.API.AuthController do
  use Phoenix.Controller, formats: [:json]

  alias Burble.Auth

  def register(conn, %{"email" => email, "display_name" => name, "password" => password}) do
    case Auth.register_user(%{email: email, display_name: name, password: password}) do
      {:ok, user} ->
        token = Phoenix.Token.sign(BurbleWeb.Endpoint, "user_auth", user.id)
        json(conn, %{user_id: user.id, display_name: user.display_name, token: token})

      {:error, errors} when is_map(errors) ->
        conn |> put_status(422) |> json(%{errors: errors})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{errors: %{base: [inspect(reason)]}})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    case Auth.authenticate_by_email(email, password) do
      {:ok, user} ->
        token = Phoenix.Token.sign(BurbleWeb.Endpoint, "user_auth", user.id)
        json(conn, %{user_id: user.id, display_name: user.display_name, token: token})

      {:error, _} ->
        conn |> put_status(401) |> json(%{error: "invalid_credentials"})
    end
  end

  def guest(conn, params) do
    name = Map.get(params, "display_name", "Guest")
    {:ok, guest} = Auth.create_guest_session(name)
    token = Phoenix.Token.sign(BurbleWeb.Endpoint, "user_auth", guest.id)
    json(conn, %{user_id: guest.id, display_name: guest.display_name, token: token, is_guest: true})
  end

  def magic_link(conn, %{"email" => email}) do
    case Auth.generate_magic_link(email) do
      {:ok, _token} -> json(conn, %{status: "sent"})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: reason})
    end
  end

  def logout(conn, _params) do
    json(conn, %{status: "logged_out"})
  end
end

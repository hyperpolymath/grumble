# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule GrumbleWeb.PageController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    html = File.read!(Application.app_dir(:grumble, "priv/static/index.html"))
    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
  end
end

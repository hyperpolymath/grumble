# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble.Repo — REMOVED.
#
# PostgreSQL/Ecto has been replaced by VeriSimDB (Burble.Store).
# This file is kept temporarily so any compile errors point here.
# See: lib/grumble/store.ex

defmodule Burble.Repo do
  @moduledoc """
  **Deprecated** — PostgreSQL/Ecto has been replaced by VeriSimDB.

  All persistence now goes through `Burble.Store`. This module is a
  no-op stub retained only to surface clear compile errors if any code
  still references it.
  """

  @deprecated "Use Burble.Store instead — PostgreSQL has been replaced by VeriSimDB"
  def get_by(_schema, _clauses), do: raise("Burble.Repo removed — use Burble.Store")

  @deprecated "Use Burble.Store instead — PostgreSQL has been replaced by VeriSimDB"
  def insert(_changeset), do: raise("Burble.Repo removed — use Burble.Store")
end

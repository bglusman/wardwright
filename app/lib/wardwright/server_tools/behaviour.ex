defmodule Wardwright.ServerTools.Behaviour do
  @moduledoc """
  Behaviour for trusted local Wardwright-hosted server tools.

  Elixir, Gleam, or Erlang modules loaded through `server_tools` run inside the
  Wardwright BEAM. They are an operator extension surface, not a sandbox
  boundary.
  """

  @callback spec() :: map()
  @callback run(arguments :: map(), context :: map()) :: {:ok, map()} | {:error, term()} | map()
end

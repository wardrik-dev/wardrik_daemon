defmodule WardrikDaemon.Capabilities do
  @moduledoc """
  The tools the daemon offers agents by name, beside the MCP servers `config.yaml` names and the
  `files` every Wardrik offers. An agent file names them in its `tools`. Lua and web search come
  next.
  """

  @doc "Returns the tools the daemon offers, by name, as a Wardrik's `:capabilities` takes them."
  @spec all() :: keyword()
  def all, do: []
end

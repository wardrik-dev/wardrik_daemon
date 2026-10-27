defmodule WardrikDaemon.Capabilities do
  @moduledoc """
  The tools the daemon offers agents by name, beside the MCP servers `config.yaml` names and the
  `files` every Wardrik offers. An agent file names them in its `tools`:

    * `run_lua`, Lua in a sealed sandbox, for arithmetic, reshaping data, and the time now; see
      `WardrikLua`
    * `web_search`, through Brave, with `config.yaml`'s `brave.api_key`; see `WardrikBrave`
    * `deep_research`, a topic split across angles, a subagent with the agent's tools researching
      each at once; see `WardrikResearch`
  """

  @doc "Returns the tools the Wardrik `wardrik` offers, by name, as its `:capabilities` takes them."
  @spec all(atom()) :: keyword()
  def all(wardrik),
    do: [
      run_lua: WardrikLua,
      web_search: {WardrikBrave, brave: brave(wardrik)},
      deep_research: WardrikResearch
    ]

  @doc "Returns the name the Wardrik `wardrik`'s web search holds its key under."
  @spec brave(atom()) :: atom()
  def brave(wardrik), do: Module.concat(wardrik, Brave)
end

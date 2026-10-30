defmodule WardrikDaemon.Capabilities do
  @moduledoc """
  Lists the tools the daemon offers agents by name.

  An agent file names them in its `tools`, beside MCP servers and Wardrik's own `files`:

      tools: [run_lua, web_search, deep_research]

    * `run_lua` - runs Lua in a sealed sandbox, for arithmetic, reshaping data and the current
      time. See `WardrikLua`.
    * `web_search` - searches the web through Brave. Needs `brave.api_key` in `config.yaml`.
      See `WardrikBrave`.
    * `deep_research` - splits a topic into angles, and has a subagent with the agent's own tools
      research each at once. See `WardrikResearch`.
  """

  @doc "Returns the tools by name, as Wardrik's `:capabilities` option takes them. `wardrik` is what Wardrik is reached by."
  @spec all(atom()) :: keyword()
  def all(wardrik),
    do: [
      run_lua: WardrikLua,
      web_search: {WardrikBrave, brave: brave(wardrik)},
      deep_research: WardrikResearch
    ]

  @doc "Returns the name `WardrikBrave` runs under for `wardrik`, as `MyWardrik.Brave`."
  @spec brave(atom()) :: atom()
  def brave(wardrik), do: Module.concat(wardrik, Brave)
end

defmodule WardrikDaemon.CLI.Init do
  @moduledoc """
  Writes `wardrik init`'s files: what a new deployment starts from.

    * `config.yaml` - with the org and the default model.
    * `agents/assistant.md` - the front door.

  The front door searches the web with `web_search` where `BRAVE_API_KEY` is set. Elsewhere
  `config.yaml` says how to turn it on.
    * `env` - for the keys `config.yaml` names. Only you can read it.

  A file that's already there is kept.

  The front door is the agent you tell an outcome, as "tell me when this feed has a new post". It
  proposes the work as the calls that do it, and defines the workers once you approve them. It
  keeps what it set up in its `MEMORY.md`. Its body is its instructions, then a playbook to edit as
  you like.
  """

  alias WardrikDaemon.Dirs

  @doc """
  Writes the files in the config directory `dirs` names, for `org` and `model`, with web search
  where `search?`. Keeps any already there.
  """
  @spec run(Dirs.t(), String.t(), String.t(), boolean()) :: [{Path.t(), :written | :kept}]
  def run(dirs, org, model, search?) do
    [
      {Dirs.config(dirs, "config.yaml"), config(org, model, search?), 0o644},
      {Dirs.config(dirs, "agents/assistant.md"), assistant(search?), 0o644},
      {Dirs.config(dirs, "env"), env(), 0o600}
    ]
    |> Enum.map(&written/1)
  end

  defp written({path, text, mode}) do
    if File.exists?(path) do
      {path, :kept}
    else
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, text)
      File.chmod!(path, mode)
      {path, :written}
    end
  end

  defp config(org, model, search?) do
    """
    # What the daemon reads as it starts. Restart it after a change.
    org: #{org}

    defaults:
      model: #{model}

    http:
      port: 4747

    """ <> brave(search?)
  end

  defp brave(true) do
    """
    # web_search searches the web through Brave with this key.
    brave:
      api_key: ${BRAVE_API_KEY}
    """
  end

  defp brave(false) do
    """
    # web_search searches the web through Brave. To turn it on, set BRAVE_API_KEY in env or seal it
    # with `wardrik vault put BRAVE_API_KEY`, uncomment these lines, and add web_search to the tools
    # in agents/assistant.md.
    # brave:
    #   api_key: ${BRAVE_API_KEY}
    """
  end

  defp assistant(search?) do
    tools =
      if search?,
        do: "self/*, agents/*, files, web_search, run_lua",
        else: "self/*, agents/*, files, run_lua"

    """
    ---
    description: "The front door: turns what people ask for into work that runs."
    tools: [#{tools}]
    context: [MEMORY.md]
    policy: {budget: {tokens: 2000000, per: day}}
    idle_timeout: infinity
    ---
    """ <> File.read!(Application.app_dir(:wardrik_daemon, "priv/front_door.md"))
  end

  defp env do
    """
    # Keys the daemon reads where its environment doesn't set them, one NAME=value a line.
    # ANTHROPIC_API_KEY=sk-ant-...
    # BRAVE_API_KEY=...
    """
  end
end

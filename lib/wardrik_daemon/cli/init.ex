defmodule WardrikDaemon.CLI.Init do
  @moduledoc """
  Writes what a new deployment starts from, where nothing is there yet: `config.yaml`, an agent to
  talk to in `agents/assistant.md`, and an `env` file, which only you can read, for the keys
  `config.yaml` names.
  """

  alias WardrikDaemon.Dirs

  @doc "Writes the files `dirs` names for the org `org` and the model `model`, keeping any already there."
  @spec run(Dirs.t(), String.t(), String.t()) :: [{Path.t(), :written | :kept}]
  def run(dirs, org, model) do
    [
      {Dirs.config(dirs, "config.yaml"), config(org, model), 0o644},
      {Dirs.config(dirs, "agents/assistant.md"), assistant(), 0o644},
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

  defp config(org, model) do
    """
    # What the daemon reads as it starts. Restart it after a change.
    org: #{org}

    defaults:
      model: #{model}

    http:
      port: 4747
    """
  end

  defp assistant do
    """
    ---
    description: Answers questions, briefly.
    ---
    You help whoever asks. Keep answers short.
    """
  end

  defp env do
    """
    # Keys the daemon reads where its environment doesn't set them, one NAME=value a line.
    # ANTHROPIC_API_KEY=sk-ant-...
    """
  end
end

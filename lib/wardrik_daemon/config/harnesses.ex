defmodule WardrikDaemon.Config.Harnesses do
  @moduledoc """
  Reads `config.yaml`'s `harnesses` and `checkouts`: the coding agents agents may call, and the
  git repositories they work in.

      harnesses:
        claude:
          command: claude-agent-acp
          env: {ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"}
          meta: {claudeCode: {options: {settingSources: []}}}
          options: {mode: default}
          context: [CLAUDE.md, AGENTS.md]
          timeout: 1800
      checkouts:
        billing: ~/src/billing

    * Each harness is a tool of the same name: an agent file lists `tools: [claude]`.
    * A harness takes `WardrikACP.Harness`'s options. `timeout` and `idle` are in seconds.
    * A checkout is a git repository with a commit. Worktrees go in the data directory's
      `worktrees`.
    * A harness no entry in `orgs` lists is the deployment's org's.
  """

  alias WardrikDaemon.Config.Options

  @seconds [:timeout, :idle]

  @doc "Returns the harnesses `section` names, as `WardrikACP` takes them, or the key that doesn't read."
  @spec read(map()) :: {:ok, keyword()} | {:error, String.t()}
  def read(section) do
    Options.loaded([WardrikACP.Harness])
    Options.each(section, &harness/2)
  end

  @doc "Returns the checkouts `section` names, each with its path expanded."
  @spec checkouts(map()) :: {:ok, keyword()} | {:error, String.t()}
  def checkouts(section), do: Options.each(section, &checkout/2)

  defp harness(name, harness) when is_map(harness) do
    path = "harnesses.#{name}"

    with {:ok, opts} <- Options.convert(harness, [], path),
         opts = Enum.map(opts, &option/1),
         {:ok, _harness} <- Options.built(fn -> WardrikACP.Harness.new!(name, opts) end, path) do
      {:ok, opts}
    end
  end

  defp harness(name, _harness),
    do: {:error, "harnesses.#{name}: is a harness's keys, with a command"}

  defp option({key, seconds}) when key in @seconds and is_number(seconds),
    do: {key, round(seconds * 1000)}

  defp option(option), do: option

  defp checkout(_name, path) when is_binary(path), do: {:ok, Path.expand(path)}
  defp checkout(name, _path), do: {:error, "checkouts.#{name}: is a repository's path"}
end

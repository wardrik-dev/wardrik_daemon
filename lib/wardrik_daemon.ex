defmodule WardrikDaemon do
  @moduledoc """
  Runs Wardrik as a daemon, on a machine of yours, with no app around it.

    * Agents are Markdown files in `agents/`. See `WardrikDaemon.AgentFile`.
    * The deployment is set up in `config.yaml`. See `WardrikDaemon.Config`.
    * People and programs reach it over its HTTP API, or with the `wardrik` command.
      See `WardrikDaemon.CLI`.

  `WardrikDaemon.Server` is what runs.
  """

  @doc "Returns `value` from `{:ok, value}`. Raises `ArgumentError` with the reason for `{:error, reason}`."
  @spec ok!({:ok, value} | {:error, String.t()}) :: value when value: term()
  def ok!({:ok, value}), do: value
  def ok!({:error, why}), do: raise(ArgumentError, why)
end

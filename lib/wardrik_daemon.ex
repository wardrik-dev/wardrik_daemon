defmodule WardrikDaemon do
  @moduledoc """
  Wardrik as a daemon: agents from files in `agents/`, the deployment in `config.yaml`, an HTTP API,
  and the `wardrik` command. See `WardrikDaemon.Server` for what runs, `WardrikDaemon.Config` for
  what `config.yaml` takes, and `WardrikDaemon.CLI` for the commands.

  Reach for this when you want agents running on a machine of yours, with no app around them.
  """

  @doc "Returns the value of `{:ok, value}`, or raises with why it isn't one."
  @spec ok!({:ok, value} | {:error, String.t()}) :: value when value: term()
  def ok!({:ok, value}), do: value
  def ok!({:error, why}), do: raise(ArgumentError, why)
end

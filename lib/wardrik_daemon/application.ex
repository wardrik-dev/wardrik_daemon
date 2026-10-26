defmodule WardrikDaemon.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    env = System.get_env()
    children = if env["WARDRIK_SERVE"] == "1", do: [{WardrikDaemon.Server, env: env}], else: []
    Supervisor.start_link(children, strategy: :one_for_one, name: WardrikDaemon.Supervisor)
  end
end

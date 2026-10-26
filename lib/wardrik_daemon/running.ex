defmodule WardrikDaemon.Running do
  @moduledoc """
  The daemon once its store runs: it reads the config, with `${NAME}` from the vault where the
  environment doesn't set it, and the policies, then runs the Wardrik, the HTTP API, and, once
  they're up, defines the agents its files declare and writes the `wardrik` command's token.
  """

  use Supervisor

  require Logger

  alias WardrikCore.Principal
  alias WardrikDaemon.Agents
  alias WardrikDaemon.CLIToken
  alias WardrikDaemon.Config
  alias WardrikDaemon.Dirs
  alias WardrikDaemon.Policies

  @doc "Starts what runs once the store does, with the options `WardrikDaemon.Server` gives it."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

  @impl Supervisor
  def init(opts) do
    %{name: name, dirs: dirs, env: env, store: store, keys: keys} = Map.new(opts)

    config = WardrikDaemon.ok!(Config.read(dirs, env, sealed(store, keys)))
    policies = WardrikDaemon.ok!(Policies.read(Dirs.config(dirs, "policies")))

    agents = [
      wardrik: name,
      dir: Dirs.config(dirs, "agents"),
      config: config,
      store: WardrikStore.scope(store, "wardrik_daemon")
    ]

    wardrik =
      Wardrik.new(
        name: name,
        capabilities: opts[:capabilities] || WardrikDaemon.Capabilities.all(),
        store: store,
        keys: keys,
        oauth: oauth(config),
        mcp: config.mcp,
        channels: config.channels,
        policies: Map.to_list(policies),
        declarations: {Agents, agents}
      )

    children = [
      {Wardrik, wardrik},
      {WardrikHTTP, wardrik: name, port: config.port, ip: config.ip},
      %{
        id: :started,
        start: {Task, :start_link, [fn -> started(agents, dirs, config) end]},
        restart: :transient
      }
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "Returns how the config finds the deployment's secret `name` in the vault."
  @spec sealed(WardrikStore.t(), [String.t()]) :: Config.vault()
  def sealed(store, keys) do
    fn name ->
      case WardrikVault.read(store, keys, %Principal{id: "deployment"}, name) do
        {:ok, value} -> {:ok, value}
        {:error, _reason} -> :error
      end
    end
  end

  defp oauth(%Config{oauth: []}), do: nil
  defp oauth(config), do: [page: Config.base_url(config) <> "/oauth", providers: config.oauth]

  defp started(agents, dirs, config) do
    Enum.each(config.warnings, &Logger.warning("config.yaml: #{&1}"))
    :ok = Agents.reload(agents)
    :ok = CLIToken.issue(agents[:wardrik], Dirs.data_home(dirs, "cli_token"), Config.url(config))
    :telemetry.execute([:wardrik_daemon, :started], %{}, %{wardrik: agents[:wardrik]})
  end
end

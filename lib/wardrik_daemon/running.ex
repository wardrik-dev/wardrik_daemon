defmodule WardrikDaemon.Running do
  @moduledoc """
  Runs the daemon once its store is up. `WardrikDaemon.Server` starts it.

  It reads `config.yaml` and `policies/`, filling in each `${NAME}` the environment doesn't set from
  the vault. Then it starts, in order:

    1. `WardrikBrave`, for `web_search`.
    2. Wardrik.
    3. The HTTP API, as `Wardrik.HTTP`.
    4. A task that defines the agents in `agents/`, writes the `wardrik` command's token, and
       emits `[:wardrik_daemon, :started]`.
  """

  use Supervisor

  require Logger

  alias WardrikCore.Principal
  alias WardrikDaemon.Agents
  alias WardrikDaemon.CLIToken
  alias WardrikDaemon.Config
  alias WardrikDaemon.Dirs
  alias WardrikDaemon.Policies

  @doc "Starts it, with the options `WardrikDaemon.Server` passes."
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
        capabilities: opts[:capabilities] || WardrikDaemon.Capabilities.all(name),
        store: store,
        keys: keys,
        oauth: oauth(config),
        mcp: config.mcp,
        channels: config.channels,
        notify: config.notify,
        workspace: config.workspace,
        defaults: config.defaults,
        prices: config.prices,
        policies: Map.to_list(policies),
        orgs: {WardrikDaemon.Orgs, %{org: config.org, orgs: config.orgs, policies: policies}},
        trusted_workers: config.trusted_workers,
        egress: &Wardrik.Egress.any/1,
        declarations: {Agents, agents}
      )

    children = [
      {WardrikBrave, name: WardrikDaemon.Capabilities.brave(name), api_key: config.brave},
      {Wardrik, wardrik},
      {Wardrik.HTTP, wardrik: name, port: config.port, ip: config.ip},
      %{
        id: :started,
        start: {Task, :start_link, [fn -> started(agents, dirs, config) end]},
        restart: :transient
      }
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "Returns a `t:WardrikDaemon.Config.vault/0` that reads the deployment's secrets from `store` with `keys`."
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
    _problems = Agents.reload(agents)
    :ok = CLIToken.issue(agents[:wardrik], Dirs.data_home(dirs, "cli_token"), Config.url(config))
    :telemetry.execute([:wardrik_daemon, :started], %{}, %{wardrik: agents[:wardrik]})
  end
end

defmodule WardrikDaemon.Server do
  @moduledoc """
  Runs the daemon: a store under the data directory, the Wardrik that runs its agents, the HTTP
  API, and, once they're up, the agents its files declare and the token the `wardrik` command acts
  with. It emits `[:wardrik_daemon, :started]` once they are.

  It takes `:env`, the environment it reads its directories and `${NAME}`s from, `:name`, what its
  Wardrik is reached by, `:capabilities`, the tools agents may name, and, for tests, `:store` in
  place of the one on disk.
  """

  use Supervisor

  require Logger

  alias WardrikDaemon.Agents
  alias WardrikDaemon.CLIToken
  alias WardrikDaemon.Config
  alias WardrikDaemon.Dirs
  alias WardrikDaemon.EnvFile
  alias WardrikDaemon.Policies

  @doc "Starts the daemon. Raises where its config or policies don't read, saying why."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Supervisor
  def init(opts) do
    name = Keyword.get(opts, :name, WardrikDaemon.Wardrik)
    given = Keyword.fetch!(opts, :env)
    dirs = Dirs.new(given)
    env = EnvFile.load(dirs.env_file, given)
    System.put_env(env)

    config = ok!(Config.read(dirs, env))
    policies = ok!(Policies.read(Dirs.config(dirs, "policies")))

    store =
      Keyword.get_lazy(opts, :store, fn ->
        WardrikStore.EKV.new(name: Module.concat(name, Store), data_dir: dirs.data)
      end)

    keys = keys(config, dirs, env)

    agents = [
      wardrik: name,
      dir: Dirs.config(dirs, "agents"),
      config: config,
      store: WardrikStore.scope(store, "wardrik_daemon")
    ]

    children = [
      {WardrikStore, store},
      {Wardrik, wardrik(name, config, store, keys, policies, agents, opts[:capabilities] || [])},
      {WardrikHTTP, wardrik: name, port: config.port, ip: config.ip},
      %{
        id: :started,
        start: {Task, :start_link, [fn -> started(agents, dirs, config) end]},
        restart: :transient
      }
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp wardrik(name, config, store, keys, policies, agents, capabilities) do
    Wardrik.new(
      name: name,
      capabilities: capabilities,
      store: store,
      keys: keys,
      oauth: oauth(config),
      mcp: config.mcp,
      channels: config.channels,
      policies: Map.to_list(policies),
      declarations: {Agents, agents}
    )
  end

  defp oauth(%Config{oauth: []}), do: nil
  defp oauth(config), do: [page: Config.base_url(config) <> "/oauth", providers: config.oauth]

  defp started(agents, dirs, config) do
    Enum.each(config.warnings, &Logger.warning("config.yaml: #{&1}"))
    :ok = Agents.reload(agents)
    :ok = CLIToken.issue(agents[:wardrik], Dirs.data_home(dirs, "cli_token"), Config.url(config))
    :telemetry.execute([:wardrik_daemon, :started], %{}, %{wardrik: agents[:wardrik]})
  end

  defp keys(%Config{keys: [_ | _] = keys}, _dirs, _env), do: keys
  defp keys(_config, _dirs, %{"WARDRIK_VAULT_KEY" => key}), do: [key]
  defp keys(_config, dirs, _env), do: [vault_key(Dirs.data_home(dirs, "vault_key"))]

  defp vault_key(path) do
    case File.read(path) do
      {:ok, key} ->
        String.trim(key)

      {:error, :enoent} ->
        key = WardrikVault.generate_key()
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, key)
        File.chmod!(path, 0o600)
        key
    end
  end

  defp ok!({:ok, value}), do: value
  defp ok!({:error, why}), do: raise(ArgumentError, why)
end

defmodule WardrikDaemon.Server do
  @moduledoc """
  Runs the daemon in two stages. First its store, under the data directory, so the vault can be
  read. Then `WardrikDaemon.Running`, which reads the config with the vault's secrets and runs the
  rest. It emits `[:wardrik_daemon, :started]` once the agents its files declare are defined.

  It takes `:env`, the environment it reads its directories and `${NAME}`s from, `:name`, what its
  Wardrik is reached by, `:capabilities`, the tools agents may name, and, for tests, `:store` in
  place of the one on disk.
  """

  use Supervisor

  alias WardrikDaemon.Config
  alias WardrikDaemon.Dirs
  alias WardrikDaemon.EnvFile

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

    boot = WardrikDaemon.ok!(Config.bootstrap(dirs, env))

    store =
      Keyword.get_lazy(opts, :store, fn ->
        WardrikStore.EKV.new(name: Module.concat(name, Store), data_dir: dirs.data)
      end)

    running = [
      name: name,
      dirs: dirs,
      env: env,
      store: store,
      keys: keys(boot.keys, dirs, env),
      capabilities: Keyword.get(opts, :capabilities, [])
    ]

    Supervisor.init([{WardrikStore, store}, {WardrikDaemon.Running, running}],
      strategy: :rest_for_one
    )
  end

  defp keys([_ | _] = keys, _dirs, _env), do: keys
  defp keys([], _dirs, %{"WARDRIK_VAULT_KEY" => key}), do: [key]
  defp keys([], dirs, _env), do: [vault_key(Dirs.data_home(dirs, "vault_key"))]

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
end

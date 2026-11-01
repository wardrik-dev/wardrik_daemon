defmodule WardrikDaemon.Agents do
  @moduledoc """
  Defines the agents in `agents/`. It's the daemon's `Wardrik.Declarations`.

  On each reload, if `config.yaml` or `policies/` changed since the daemon started, the daemon
  restarts to read them, and defines the agents as it starts. Otherwise:

    * an agent whose file reads is defined from it.
    * an agent whose file is gone is forgotten.
    * an agent whose file doesn't read keeps its last definition, and the log says why.

  The API can't forget an agent a file declares.

  ## Options

    * `:wardrik` - what Wardrik is reached by.
    * `:dir` - the `agents/` directory.
    * `:config` - the `WardrikDaemon.Config` read as the daemon started.
    * `:restart` - restarts the daemon if `config.yaml` or `policies/` changed since it started.
      Returns whether it does.
    * `:store` - where it keeps which agents the files declare.
  """

  @behaviour Wardrik.Declarations

  require Logger

  alias WardrikCore.Principal
  alias WardrikDaemon.AgentFile

  @key "agent files"

  @impl Wardrik.Declarations
  def declared?(opts, id), do: id in Map.values(declared(opts))

  @impl Wardrik.Declarations
  def reload(opts) do
    restart = opts[:restart] || fn -> false end
    if restart.(), do: [], else: defined_all(opts)
  end

  defp defined_all(opts) do
    scope = scope(opts)
    last = declared(opts)
    read = opts |> files() |> Enum.map(&{&1, AgentFile.read(&1, opts[:config])})

    declared =
      for {path, result} <- read,
          file = Path.basename(path),
          id = declares(result, last[file]),
          into: %{},
          do: {file, id}

    gone = Enum.uniq(Map.values(last)) -- Map.values(declared)

    {:ok, _vsn} = WardrikStore.put(opts[:store], @key, declared)
    problems = Enum.map(read, &defined(scope, &1)) ++ Enum.map(gone, &forgotten(scope, &1))
    for problem <- problems, problem != :ok, do: logged(problem)
  end

  defp logged(problem) do
    Logger.warning("Wardrik #{problem}")
    problem
  end

  @doc "Returns the scope agents are defined in: the deployment's own, as owner of every resource."
  @spec scope(keyword()) :: Wardrik.Scope.t()
  def scope(opts),
    do:
      Wardrik.as(opts[:wardrik], %Principal{id: "deployment"}, roles: [:owner], resources: ["*"])

  defp files(opts), do: opts[:dir] |> Path.join("*.md") |> Path.wildcard() |> Enum.sort()

  defp declared(opts), do: WardrikStore.get(opts[:store], @key) || %{}

  defp declares({:ok, id, _definition}, _last), do: id
  defp declares({:error, _why}, last), do: last

  defp defined(_scope, {_path, {:error, why}}), do: "didn't read an agent. #{why}"

  defp defined(scope, {path, {:ok, id, definition}}) do
    case Wardrik.run(scope, "agent.define", Map.put(definition, "agent", id)) do
      {:ok, _snapshot} -> :ok
      {:error, error} -> "didn't define #{id}. #{path}: #{error.message}"
    end
  end

  defp forgotten(scope, id) do
    case Wardrik.run(scope, "agent.forget", %{"agent" => id}) do
      {:ok, _forgotten} -> :ok
      {:error, error} -> "didn't forget #{id}, whose file is gone: #{error.message}"
    end
  end
end

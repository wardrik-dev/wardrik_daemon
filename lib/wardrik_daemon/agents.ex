defmodule WardrikDaemon.Agents do
  @moduledoc """
  The agents the files in `agents/` declare, as the daemon's `Wardrik.Declarations`. Reloading
  defines each agent its file writes, and forgets each one whose file is gone. An agent whose file
  doesn't read keeps what it had, and the daemon's log says why. The API may not forget an agent a
  file declares.

  It takes `:wardrik`, the instance, `:dir`, the `agents/` directory, `:config`, the
  `WardrikDaemon.Config`, and `:store`, where it keeps which agents files declare.
  """

  @behaviour Wardrik.Declarations

  require Logger

  alias WardrikCore.Principal
  alias WardrikDaemon.AgentFile

  @key "declared"

  @impl Wardrik.Declarations
  def declared?(opts, id), do: id in declared(opts)

  @impl Wardrik.Declarations
  def reload(opts) do
    scope = scope(opts)
    read = opts |> files() |> Enum.map(&{&1, AgentFile.read(&1, opts[:config])})
    declared = for {_path, {:ok, id, _definition}} <- read, do: id
    gone = declared(opts) -- declared

    {:ok, _vsn} = WardrikStore.put(opts[:store], @key, declared)
    problems = Enum.map(read, &defined(scope, &1)) ++ Enum.map(gone, &forgotten(scope, &1))
    for problem <- problems, problem != :ok, do: logged(problem)
  end

  defp logged(problem) do
    Logger.warning("Wardrik #{problem}")
    problem
  end

  @doc "Returns the scope files define agents in: the deployment's own, which may do anything."
  @spec scope(keyword()) :: Wardrik.Scope.t()
  def scope(opts),
    do:
      Wardrik.as(opts[:wardrik], %Principal{id: "deployment"}, roles: [:owner], resources: ["*"])

  defp files(opts), do: opts[:dir] |> Path.join("*.md") |> Path.wildcard() |> Enum.sort()

  defp declared(opts), do: WardrikStore.get(opts[:store], @key) || []

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

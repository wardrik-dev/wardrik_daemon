defmodule WardrikDaemon.Doctor.Agents do
  @moduledoc """
  Checks every agent file and policy as the daemon reads them: each file's definition against the
  protocol's schema, then as the Wardrik would start it, with the tools, servers, channels and
  policies the daemon offers. Nothing is started but a store in memory.
  """

  alias Wardrik.Definition
  alias WardrikDaemon.AgentFile
  alias WardrikDaemon.Config
  alias WardrikDaemon.Dirs
  alias WardrikDaemon.Policies

  import WardrikDaemon.Doctor, only: [counted: 2]

  @doc "Returns a line for each file that doesn't read, or one saying they all did."
  @spec check(Config.t(), Dirs.t()) :: [WardrikDaemon.Doctor.check()]
  def check(config, dirs) do
    case Policies.read(Dirs.config(dirs, "policies")) do
      {:ok, policies} -> agents(config, dirs, policies)
      {:error, why} -> [{:fail, "agents", why}]
    end
  end

  defp agents(config, dirs, policies) do
    files = dirs |> Dirs.config("agents") |> Path.join("*.md") |> Path.wildcard() |> Enum.sort()
    store = WardrikStore.ETS.new(name: :"wardrik doctor #{System.unique_integer([:positive])}")
    {:ok, running} = Supervisor.start_link([{WardrikStore, store}], strategy: :one_for_one)

    wardrik = wardrik(config, policies, store)
    schema = JSV.build!(WardrikProtocol.schema("agent_definition"))
    failures = Enum.flat_map(files, &unread(&1, config, wardrik, schema))
    :ok = Supervisor.stop(running)

    case failures do
      [] ->
        [
          {:ok, "agents",
           "#{counted(length(files), "agent file")} and #{counted(map_size(policies), "policy")} read"}
        ]

      failures ->
        failures
    end
  end

  defp unread(path, config, wardrik, schema) do
    with {:ok, id, definition} <- AgentFile.read(path, config),
         {:ok, _valid} <- valid(definition, schema),
         {:ok, _opts} <- Definition.resolve(wardrik, id, definition) do
      []
    else
      {:error, %Wardrik.Error{message: message}} ->
        [{:fail, "agents", "#{Path.basename(path)}: #{message}"}]

      {:error, why} ->
        [{:fail, "agents", why}]
    end
  end

  defp valid(definition, schema) do
    case JSV.validate(definition, schema) do
      {:ok, valid} ->
        {:ok, valid}

      {:error, error} ->
        {:error, %Wardrik.Error{type: :invalid_request, message: Exception.message(error)}}
    end
  end

  defp wardrik(config, policies, store) do
    Wardrik.new(
      name: WardrikDaemon.Doctor,
      store: store,
      capabilities: WardrikDaemon.Capabilities.all(),
      mcp: config.mcp,
      channels: config.channels,
      workspace: config.workspace,
      policies: Map.to_list(policies)
    )
  end
end

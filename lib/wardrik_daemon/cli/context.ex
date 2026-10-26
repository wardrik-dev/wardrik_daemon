defmodule WardrikDaemon.CLI.Context do
  @moduledoc "What every command runs with: the directories, the environment, and the deployment's org."

  alias WardrikDaemon.Client
  alias WardrikDaemon.CLIToken
  alias WardrikDaemon.Dirs

  @enforce_keys [:dirs, :env, :org]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{dirs: Dirs.t(), env: %{String.t() => String.t()}, org: String.t()}

  @doc "Returns the context `env`, the environment, gives the commands."
  @spec new(%{String.t() => String.t()}) :: t()
  def new(env) do
    dirs = Dirs.new(env)
    %__MODULE__{dirs: dirs, env: env, org: org(dirs)}
  end

  @doc "Runs the operation `id` on the daemon, and returns what it answers, or why it couldn't."
  @spec call(t(), String.t(), map()) :: {:ok, map() | nil} | {:error, String.t()}
  def call(cx, id, input) do
    with {:ok, client} <- client(cx), do: called(Client.run(client, id, input))
  end

  @doc "Returns what an operation answered, with its error as a message."
  @spec called({:ok, term()} | Client.error()) :: {:ok, term()} | {:error, String.t()}
  def called({:ok, answer}), do: {:ok, answer}
  def called({:error, _type, message}), do: {:error, message}

  @doc "Returns the client that reaches the daemon: as `WARDRIK_URL` and `WARDRIK_TOKEN` say, or with its token."
  @spec client(t()) :: {:ok, Client.t()} | {:error, String.t()}
  def client(%__MODULE__{env: %{"WARDRIK_URL" => url, "WARDRIK_TOKEN" => secret}}),
    do: {:ok, %Client{url: url, secret: secret}}

  def client(cx) do
    case CLIToken.read(Dirs.data_home(cx.dirs, "cli_token")) do
      {:ok, %{url: url, secret: secret}} ->
        {:ok, %Client{url: url, secret: secret}}

      :error ->
        {:error,
         "The daemon hasn't started here yet, so there's no token to reach it with. Start it with `wardrik start`."}
    end
  end

  @doc "Returns the ID of the agent `name` names: itself, or with the deployment's org before it."
  @spec agent(t(), String.t()) :: String.t()
  def agent(cx, name) do
    if String.contains?(name, "/") and not String.starts_with?(name, "@"),
      do: name,
      else: cx.org <> "/" <> name
  end

  @doc "Returns the owner `flags` name: `--org`, `--user` of the org, or the deployment."
  @spec owner(t(), map()) :: String.t()
  def owner(_cx, %{org: org}), do: org
  def owner(cx, %{user: user}), do: "#{cx.org}/@#{String.trim_leading(user, "@")}"
  def owner(_cx, _flags), do: "deployment"

  @doc "Puts `value` in `map` under `key`, unless it's `nil`."
  @spec put(map(), String.t(), term()) :: map()
  def put(map, _key, nil), do: map
  def put(map, key, value), do: Map.put(map, key, value)

  defp org(dirs) do
    case YamlElixir.read_from_file(Dirs.config(dirs, "config.yaml")) do
      {:ok, %{"org" => org}} when is_binary(org) -> org
      _none -> "default"
    end
  end
end

defmodule WardrikDaemon.CLI.Context do
  @moduledoc """
  What every command runs with: the directories, the environment, the deployment's org, the
  terminal it writes to, the name it was typed as, and whether it answers with JSON.
  """

  alias WardrikDaemon.CLI.Terminal
  alias WardrikDaemon.Client
  alias WardrikDaemon.CLIToken
  alias WardrikDaemon.Dirs

  @enforce_keys [:dirs, :env, :org, :terminal, :program]
  defstruct @enforce_keys ++ [json?: false]

  @type t() :: %__MODULE__{
          dirs: Dirs.t(),
          env: %{String.t() => String.t()},
          org: String.t(),
          terminal: Terminal.t(),
          program: String.t(),
          json?: boolean()
        }

  @doc "Returns the context `env`, the environment, gives the commands."
  @spec new(%{String.t() => String.t()}) :: t()
  def new(env) do
    dirs = Dirs.new(env)

    %__MODULE__{
      dirs: dirs,
      env: env,
      org: org(dirs),
      terminal: Terminal.new(env),
      program: Map.get(env, "WARDRIK_PROGRAM", "wardrik")
    }
  end

  @doc "Writes `answer` as JSON where the command was given `--json`, and as `shown` says where not."
  @spec show(t(), term(), (term() -> term())) :: :ok
  def show(%__MODULE__{json?: true}, answer, _shown), do: IO.puts(JSON.encode!(answer))

  def show(_cx, answer, shown) do
    shown.(answer)
    :ok
  end

  @doc "Writes `said` once a change is done, or what it answered where the command was given `--json`."
  @spec done(t(), term(), Owl.Data.t()) :: :ok
  def done(cx, answer, said),
    do: show(cx, answer || %{"ok" => true}, fn _answer -> puts(cx, said) end)

  @doc "Writes `data` to the command's terminal."
  @spec puts(t(), Owl.Data.t()) :: :ok
  def puts(cx, data), do: Terminal.puts(cx.terminal, data)

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
         "The daemon hasn't started here yet, so there's no token to reach it with. Start it with `#{cx.program} start`."}
    end
  end

  @doc "Returns the ID of the agent `name` names: itself, or with the deployment's org before it."
  @spec agent(t(), String.t()) :: String.t()
  def agent(cx, name) do
    if String.contains?(name, "/") and not String.starts_with?(name, "@"),
      do: name,
      else: cx.org <> "/" <> name
  end

  @doc "Returns the owner `flags` name: `--org`, `--user` of the org, or else `default`."
  @spec owner(t(), map(), String.t()) :: String.t()
  def owner(cx, flags, default \\ "deployment")
  def owner(_cx, %{org: org}, _default), do: org
  def owner(cx, %{user: user}, _default), do: "#{cx.org}/@#{String.trim_leading(user, "@")}"
  def owner(_cx, _flags, default), do: default

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

defmodule WardrikDaemon.Config do
  @moduledoc """
  The config is what `config.yaml` says, read as the daemon starts: the deployment's `org`, its
  `base_url`, the `defaults` agents start from, the `mcp` servers, `oauth` providers and
  `channels` they reach, the `vault`'s keys, and where `http` listens.

  `${NAME}` in any string is replaced with that environment variable, one the env file sets, or
  the deployment's secret of that name in the vault, which `wardrik vault put NAME` seals. `vault`
  and `http` read the environment alone, since they're read before the vault opens. A key nothing
  takes is refused, and says where. A section the daemon doesn't run yet, as `brave` or
  `notify`, is passed over with a warning.
  """

  alias WardrikDaemon.Config.Channels
  alias WardrikDaemon.Config.MCP
  alias WardrikDaemon.Config.OAuth
  alias WardrikDaemon.Dirs

  @read ~w(org base_url defaults mcp oauth channels workspace vault http)
  @bootstrap ~w(vault http)
  @later ~w(orgs tools notify brave tokens storage cluster ssh)

  defstruct org: "default",
            base_url: nil,
            defaults: %{},
            mcp: [],
            oauth: [],
            channels: [],
            workspace: [],
            keys: [],
            port: 4747,
            ip: {127, 0, 0, 1},
            warnings: []

  @type t() :: %__MODULE__{
          org: String.t(),
          base_url: String.t() | nil,
          defaults: map(),
          mcp: keyword(),
          oauth: keyword(),
          channels: keyword(),
          workspace: keyword(),
          keys: [String.t()],
          port: :inet.port_number(),
          ip: :inet.ip_address(),
          warnings: [String.t()]
        }

  @typedoc "Finds the deployment's secret `name` in the vault, or returns `:error`."
  @type vault() :: (String.t() -> {:ok, String.t()} | :error)

  @doc """
  Reads `config.yaml` in the config directory, with `${NAME}` from `env`, then from `vault`. A
  missing file reads as the defaults.
  """
  @spec read(Dirs.t(), %{String.t() => String.t()}, vault() | nil) ::
          {:ok, t()} | {:error, String.t()}
  def read(dirs, env, vault \\ nil) do
    path = Dirs.config(dirs, "config.yaml")

    with {:ok, yaml} <- yaml(path),
         :ok <- known(yaml),
         {:ok, early} <-
           interpolated(Map.take(yaml, @bootstrap), env, nil),
         {:ok, late} <- interpolated(Map.take(yaml, @read -- @bootstrap), env, vault),
         {:ok, config} <- sections(Map.merge(early, late)) do
      {:ok, %{config | warnings: later(yaml)}}
    else
      {:error, why} -> {:error, "#{path}: #{why}"}
    end
  end

  @doc "Reads what's needed before the vault opens: its keys, and where HTTP listens, from `env` alone."
  @spec bootstrap(Dirs.t(), %{String.t() => String.t()}) ::
          {:ok, %{keys: [String.t()], port: :inet.port_number(), ip: :inet.ip_address()}}
          | {:error, String.t()}
  def bootstrap(dirs, env) do
    path = Dirs.config(dirs, "config.yaml")

    with {:ok, yaml} <- yaml(path),
         :ok <- known(yaml),
         {:ok, early} <- interpolated(Map.take(yaml, @bootstrap), env, nil),
         {:ok, keys} <- keys(early["vault"]),
         {:ok, port, ip} <- http(early["http"]) do
      {:ok, %{keys: keys, port: port, ip: ip}}
    else
      {:error, why} -> {:error, "#{path}: #{why}"}
    end
  end

  @doc "Returns the `${NAME}`s `config.yaml` names outside `vault` and `http`, which the vault may hold."
  @spec sealable(Dirs.t()) :: [String.t()]
  def sealable(dirs) do
    case yaml(Dirs.config(dirs, "config.yaml")) do
      {:ok, yaml} -> yaml |> Map.take(@read -- @bootstrap) |> names() |> Enum.uniq()
      {:error, _why} -> []
    end
  end

  @doc "Returns where the HTTP API listens, as a URL on loopback or the address it's bound to."
  @spec url(t()) :: String.t()
  def url(%__MODULE__{ip: {0, 0, 0, 0}, port: port}), do: "http://127.0.0.1:#{port}"
  def url(%__MODULE__{ip: ip, port: port}), do: "http://#{:inet.ntoa(ip)}:#{port}"

  @doc "Returns the address people and services reach the deployment at: `base_url`, or the HTTP API's."
  @spec base_url(t()) :: String.t()
  def base_url(%__MODULE__{base_url: nil} = config), do: url(config)
  def base_url(%__MODULE__{base_url: base_url}), do: String.trim_trailing(base_url, "/")

  defp yaml(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, yaml} when is_map(yaml) -> {:ok, yaml}
      {:ok, nil} -> {:ok, %{}}
      {:ok, _other} -> {:error, "is a set of keys"}
      {:error, %YamlElixir.FileNotFoundError{}} -> {:ok, %{}}
      {:error, error} -> {:error, "isn't YAML: #{Exception.message(error)}"}
    end
  end

  defp known(yaml) do
    case Enum.find(Map.keys(yaml), &(&1 not in @read and &1 not in @later)) do
      nil -> :ok
      key -> {:error, "#{key}: isn't a key of config.yaml"}
    end
  end

  defp later(yaml),
    do:
      for(
        key <- @later,
        Map.has_key?(yaml, key),
        do: "#{key} isn't supported here yet, so it's passed over"
      )

  defp sections(read) do
    org = Map.get(read, "org", "default")

    with {:ok, mcp} <- MCP.read(read["mcp"]),
         {:ok, oauth} <- OAuth.read(read["oauth"]),
         {:ok, channels} <- Channels.read(read["channels"], org),
         {:ok, workspace} <- workspace(read["workspace"]),
         {:ok, keys} <- keys(read["vault"]),
         {:ok, port, ip} <- http(read["http"]),
         {:ok, defaults} <- defaults(read["defaults"]) do
      {:ok,
       %__MODULE__{
         org: org,
         base_url: read["base_url"],
         defaults: defaults,
         mcp: mcp,
         oauth: oauth,
         channels: channels,
         workspace: workspace,
         keys: keys,
         port: port,
         ip: ip
       }}
    end
  end

  defp workspace(nil), do: {:ok, []}

  defp workspace(%{"shared" => shared} = workspace)
       when is_map(shared) and map_size(workspace) == 1 do
    case Enum.find(shared, fn {_tree, rule} -> not rule?(rule) end) do
      nil ->
        {:ok,
         [
           shared:
             Map.new(shared, fn {tree, rule} ->
               {tree, [read: Map.get(rule, "read", []), write: Map.get(rule, "write", [])]}
             end)
         ]}

      {tree, _rule} ->
        {:error,
         "workspace.shared.#{tree}: holds read and write, each a list of resource patterns"}
    end
  end

  defp workspace(_workspace),
    do: {:error, "workspace: holds shared, the trees agents beyond their owners may mount"}

  defp rule?(rule) when is_map(rule),
    do:
      Enum.all?(rule, fn {key, patterns} ->
        key in ["read", "write"] and is_list(patterns) and Enum.all?(patterns, &is_binary/1)
      end)

  defp rule?(_rule), do: false

  defp keys(nil), do: {:ok, []}
  defp keys(%{"keys" => keys}) when is_list(keys), do: {:ok, keys}
  defp keys(_vault), do: {:error, "vault: holds keys, a list of the vault's keys"}

  defp http(nil), do: {:ok, 4747, {127, 0, 0, 1}}

  defp http(http) when is_map(http) do
    with {:ok, ip} <- ip(Map.get(http, "ip", "127.0.0.1")) do
      case Map.get(http, "port", 4747) do
        port when is_integer(port) and port in 0..65_535 -> {:ok, port, ip}
        _other -> {:error, "http.port: is a port number"}
      end
    end
  end

  defp http(_http), do: {:error, "http: holds port and ip"}

  defp ip(text) do
    case :inet.parse_address(to_charlist(text)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _reason} -> {:error, "http.ip: is an address, as 127.0.0.1"}
    end
  end

  defp defaults(nil), do: {:ok, %{}}
  defp defaults(defaults) when is_map(defaults), do: {:ok, defaults}
  defp defaults(_defaults), do: {:error, "defaults: is what an agent's file takes"}

  defp interpolated(term, env, vault) do
    values = term |> names() |> Enum.uniq() |> Map.new(&{&1, value(&1, env, vault)})

    case for {name, :error} <- values, do: name do
      [] -> {:ok, replaced(term, values)}
      [name | _rest] -> {:error, "names ${#{name}}, which #{unset(vault)}"}
    end
  end

  defp value(name, env, vault) do
    case {Map.fetch(env, name), vault} do
      {{:ok, value}, _vault} -> {:ok, value}
      {:error, nil} -> :error
      {:error, vault} -> vault.(name)
    end
  end

  defp unset(nil), do: "neither the environment nor the env file sets"
  defp unset(_vault), do: "neither the environment, the env file nor the vault holds"

  defp names(text) when is_binary(text),
    do: for([_whole, name] <- Regex.scan(~r/\$\{(\w+)\}/, text), do: name)

  defp names(map) when is_map(map), do: Enum.flat_map(map, fn {_key, value} -> names(value) end)
  defp names(list) when is_list(list), do: Enum.flat_map(list, &names/1)
  defp names(_other), do: []

  defp replaced(text, values) when is_binary(text) do
    Regex.replace(~r/\$\{(\w+)\}/, text, fn _whole, name ->
      {:ok, value} = Map.fetch!(values, name)
      value
    end)
  end

  defp replaced(map, values) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, replaced(value, values)} end)

  defp replaced(list, values) when is_list(list), do: Enum.map(list, &replaced(&1, values))
  defp replaced(other, _values), do: other
end

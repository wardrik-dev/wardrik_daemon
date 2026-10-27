defmodule WardrikDaemon.Config do
  @moduledoc """
  The config is what `config.yaml` says, read as the daemon starts: the deployment's `org`, the
  `orgs` beside it, its `base_url`, the `defaults` agents start from, what `models` cost, the `mcp` servers, `oauth` providers and
  `channels` they reach, the `notify` targets their notices go to, the `vault`'s keys, where
  `http` listens, and the `storage` everything is kept in: Postgres, or the node's disk without it.

  `${NAME}` in any string is replaced with that environment variable, one the env file sets, or
  the deployment's secret of that name in the vault, which `wardrik vault put NAME` seals. `vault`,
  `http` and `storage` read the environment alone, since they're read before the vault opens. A key nothing
  takes is refused, and says where. A section the daemon doesn't run yet, as `cluster`, is passed
  over with a warning.
  """

  alias WardrikDaemon.Config.Channels
  alias WardrikDaemon.Config.MCP
  alias WardrikDaemon.Config.Notify
  alias WardrikDaemon.Config.OAuth
  alias WardrikDaemon.Config.Orgs
  alias WardrikDaemon.Dirs

  @read ~w(org orgs base_url defaults models mcp oauth channels notify workspace brave vault http
           storage)
  @bootstrap ~w(vault http storage)
  @later ~w(tools tokens cluster ssh)

  defstruct org: "default",
            orgs: %{},
            base_url: nil,
            defaults: %{},
            prices: %{},
            mcp: [],
            oauth: [],
            channels: [],
            notify: [],
            workspace: [],
            brave: nil,
            keys: [],
            port: 4747,
            ip: {127, 0, 0, 1},
            trusted_workers: false,
            storage: nil,
            warnings: []

  @type t() :: %__MODULE__{
          org: String.t(),
          orgs: %{String.t() => Orgs.entry()},
          base_url: String.t() | nil,
          defaults: map(),
          prices: %{String.t() => keyword()},
          mcp: keyword(),
          oauth: keyword(),
          channels: keyword(),
          notify: keyword(),
          workspace: keyword(),
          brave: String.t() | nil,
          keys: [String.t()],
          port: :inet.port_number(),
          ip: :inet.ip_address(),
          trusted_workers: boolean(),
          storage: {:postgres, String.t()} | nil,
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

  @doc """
  Reads what's needed before the vault opens, from `env` alone: its keys, where HTTP listens, and
  where everything is kept.
  """
  @spec bootstrap(Dirs.t(), %{String.t() => String.t()}) ::
          {:ok,
           %{
             keys: [String.t()],
             port: :inet.port_number(),
             ip: :inet.ip_address(),
             storage: {:postgres, String.t()} | nil
           }}
          | {:error, String.t()}
  def bootstrap(dirs, env) do
    path = Dirs.config(dirs, "config.yaml")

    with {:ok, yaml} <- yaml(path),
         :ok <- known(yaml),
         {:ok, early} <- interpolated(Map.take(yaml, @bootstrap), env, nil),
         {:ok, keys} <- keys(early["vault"]),
         {:ok, port, ip} <- http(early["http"]),
         {:ok, storage} <- storage(early["storage"]) do
      {:ok, %{keys: keys, port: port, ip: ip, storage: storage}}
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
         {:ok, notify} <- Notify.read(read["notify"], org, Enum.map(channels, &elem(&1, 0))),
         {:ok, orgs} <- Orgs.read(read["orgs"], defined(mcp, channels, notify)),
         {:ok, channels} <- owned(channels, orgs, org),
         {:ok, workspace} <- workspace(read["workspace"]),
         {:ok, brave} <- brave(read["brave"]),
         {:ok, keys} <- keys(read["vault"]),
         {:ok, port, ip} <- http(read["http"]),
         {:ok, trusted_workers} <- trusted_workers(read["http"]),
         {:ok, storage} <- storage(read["storage"]),
         {:ok, defaults} <- defaults(read["defaults"]),
         {:ok, prices} <- prices(read["models"]) do
      {:ok,
       %__MODULE__{
         org: org,
         orgs: orgs,
         base_url: read["base_url"],
         defaults: defaults,
         prices: prices,
         mcp: served(mcp, orgs, org),
         oauth: oauth,
         channels: channels,
         notify: told(notify, orgs, org),
         workspace: workspace,
         brave: brave,
         keys: keys,
         port: port,
         ip: ip,
         trusted_workers: trusted_workers,
         storage: storage
       }}
    end
  end

  defp defined(mcp, channels, notify) do
    %{
      "mcp" => Enum.map(mcp, &to_string(elem(&1, 0))),
      "channels" => Enum.map(channels, &to_string(elem(&1, 0))),
      "notify" => notify |> Keyword.get(:targets, []) |> Enum.map(&to_string(elem(&1, 0)))
    }
  end

  defp served(mcp, orgs, _org) when orgs == %{}, do: mcp

  defp served(mcp, orgs, org) do
    for {name, opts} <- mcp do
      case Orgs.using(orgs, :mcp, to_string(name), org) do
        :all -> {name, opts}
        using -> {name, opts ++ [orgs: using]}
      end
    end
  end

  defp told(notify, orgs, _org) when orgs == %{}, do: notify

  defp told(notify, orgs, org) do
    Keyword.update(notify, :targets, [], fn targets ->
      for {name, {module, opts}} <- targets do
        {name,
         {module, Keyword.delete(opts, :orgs) ++ told_orgs(Orgs.using(orgs, :notify, name, org))}}
      end
    end)
  end

  defp told_orgs(:all), do: []
  defp told_orgs(using), do: [orgs: using]

  defp owned(channels, orgs, org) do
    owned =
      for {name, {adapter, opts}} <- channels, do: {name, owner(orgs, name, org), adapter, opts}

    case Enum.find(owned, &match?({_name, {:error, _why}, _adapter, _opts}, &1)) do
      nil ->
        {:ok,
         for(
           {name, {:ok, owner}, adapter, opts} <- owned,
           do: {name, {adapter, Keyword.replace!(opts, :owner, owner)}}
         )}

      {name, {:error, why}, _adapter, _opts} ->
        {:error, "channels.#{name}: #{why}"}
    end
  end

  defp owner(orgs, name, org) do
    case Orgs.using(orgs, :channels, to_string(name), org) do
      :all ->
        {:ok, "*"}

      [owner] ->
        {:ok, owner}

      several ->
        {:error,
         "is listed by #{Enum.join(several, " and ")}; a channel serves one org, or every org under \"*\""}
    end
  end

  @rates %{
    "input" => :input,
    "output" => :output,
    "cache_read" => :cache_read,
    "cache_write" => :cache_write,
    "priced_as" => :priced_as,
    "markup" => :markup
  }

  defp prices(nil), do: {:ok, %{}}

  defp prices(models) when is_map(models) do
    priced = Map.new(models, fn {spec, price} -> {spec, price(spec, price)} end)

    case Enum.find(priced, &match?({_spec, {:error, _why}}, &1)) do
      nil -> {:ok, Map.new(priced, fn {spec, {:ok, price}} -> {spec, price} end)}
      {_spec, error} -> error
    end
  end

  defp prices(_models),
    do: {:error, "models: holds each model's price, by its spec, as zai:glm-5.1"}

  defp price(spec, price) when is_map(price) do
    case Enum.reject(Map.keys(price), &Map.has_key?(@rates, &1)) do
      [] -> checked(spec, Enum.map(price, fn {key, value} -> {@rates[key], value} end))
      [key | _rest] -> {:error, "models.#{spec}.#{key}: isn't a setting"}
    end
  end

  defp price(spec, _price),
    do:
      {:error,
       "models.#{spec}: holds input and output, dollars per million tokens, or priced_as, and markup"}

  defp checked(spec, price) do
    _priced = Wardrik.Setup.price(spec, price)
    {:ok, price}
  rescue
    error in ArgumentError ->
      {:error, "models.#{spec}: #{Exception.message(error)}"}
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

  defp brave(nil), do: {:ok, nil}

  defp brave(%{"api_key" => key} = brave) when is_binary(key) and map_size(brave) == 1,
    do: {:ok, key}

  defp brave(_brave), do: {:error, "brave: holds api_key, the key web search searches with"}

  defp storage(nil), do: {:ok, nil}

  defp storage(%{"postgres" => %{"url" => "postgres" <> _rest = url} = postgres} = storage)
       when map_size(storage) == 1 and map_size(postgres) == 1,
       do: {:ok, {:postgres, url}}

  defp storage(%{"s3" => _s3}),
    do:
      {:error,
       "storage.s3: isn't supported here yet; use postgres, or leave storage out for disk"}

  defp storage(_storage),
    do: {:error, "storage: holds postgres, with url, a postgres:// URL"}

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

  defp http(_http), do: {:error, "http: holds port, ip and trusted_workers"}

  defp trusted_workers(%{"trusted_workers" => trusted}) when is_boolean(trusted),
    do: {:ok, trusted}

  defp trusted_workers(%{"trusted_workers" => _other}),
    do: {:error, "http.trusted_workers: is true or false"}

  defp trusted_workers(_http), do: {:ok, false}

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

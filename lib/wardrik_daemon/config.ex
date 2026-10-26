defmodule WardrikDaemon.Config do
  @moduledoc """
  The config is what `config.yaml` says, read as the daemon starts: the deployment's `org`, its
  `base_url`, the `defaults` agents start from, the `mcp` servers, `oauth` providers and
  `channels` they reach, the `vault`'s keys, and where `http` listens.

  `${NAME}` in any string is replaced with that environment variable, or one the env file sets. A
  key nothing takes is refused, and says where. A section the daemon doesn't run yet, as `brave` or
  `notify`, is passed over with a warning.
  """

  alias WardrikDaemon.Config.Channels
  alias WardrikDaemon.Config.MCP
  alias WardrikDaemon.Config.OAuth
  alias WardrikDaemon.Dirs

  @read ~w(org base_url defaults mcp oauth channels vault http)
  @later ~w(orgs tools notify workspace brave tokens storage cluster ssh)

  defstruct org: "default",
            base_url: nil,
            defaults: %{},
            mcp: [],
            oauth: [],
            channels: [],
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
          keys: [String.t()],
          port: :inet.port_number(),
          ip: :inet.ip_address(),
          warnings: [String.t()]
        }

  @doc "Reads `config.yaml` in the config directory, with `${NAME}` from `env`. A missing file reads as the defaults."
  @spec read(Dirs.t(), %{String.t() => String.t()}) :: {:ok, t()} | {:error, String.t()}
  def read(dirs, env) do
    path = Dirs.config(dirs, "config.yaml")

    with {:ok, yaml} <- yaml(path),
         :ok <- known(yaml),
         {:ok, read} <- interpolated(Map.take(yaml, @read), env),
         {:ok, config} <- sections(read) do
      {:ok, %{config | warnings: later(yaml)}}
    else
      {:error, why} -> {:error, "#{path}: #{why}"}
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
         keys: keys,
         port: port,
         ip: ip
       }}
    end
  end

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

  defp interpolated(term, env) do
    case term |> names() |> Enum.reject(&Map.has_key?(env, &1)) do
      [] ->
        {:ok, replaced(term, env)}

      [name | _rest] ->
        {:error, "names ${#{name}}, which neither the environment nor the env file sets"}
    end
  end

  defp names(text) when is_binary(text),
    do: for([_whole, name] <- Regex.scan(~r/\$\{(\w+)\}/, text), do: name)

  defp names(map) when is_map(map), do: Enum.flat_map(map, fn {_key, value} -> names(value) end)
  defp names(list) when is_list(list), do: Enum.flat_map(list, &names/1)
  defp names(_other), do: []

  defp replaced(text, env) when is_binary(text),
    do: Regex.replace(~r/\$\{(\w+)\}/, text, fn _whole, name -> Map.fetch!(env, name) end)

  defp replaced(map, env) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, replaced(value, env)} end)

  defp replaced(list, env) when is_list(list), do: Enum.map(list, &replaced(&1, env))
  defp replaced(other, _env), do: other
end

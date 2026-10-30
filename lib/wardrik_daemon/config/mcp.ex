defmodule WardrikDaemon.Config.MCP do
  @moduledoc """
  Reads `config.yaml`'s `mcp`: the MCP servers agents may call, each by a name of your own.

      mcp:
        github:
          url: https://api.githubcopilot.com/mcp/
          credential: github
          only: [list_commits, get_commit]
        notes:
          command: npx
          args: [-y, notes-mcp]

  ## Keys

  A server has a `command` or a `url`, not both.

    * `command`, `args`, `env` - the program to run, over stdio.
    * `url`, `headers` - where to reach it, over streamable HTTP.
    * `only`, `except` - the server's tool names to offer, or to leave out.
    * `prefix` - the prefix for its tool names.
    * `timeout` - seconds a call may take.
    * `max_result_bytes` - bytes of a result the model gets.
    * `credential` - the credential each principal reaches it with. `credential_header`,
      `credential_scheme` and `credential_env` say where it goes.
    * `gated` - which tools need a person's approval: `true`, `false`, or tool names, as `[create_*]`.
    * `trusted` - `true` to treat its answers as the deployment's own.

  See `WardrikMCP.Server` for each one's default.
  """

  @keys ~w(command args env url headers only except prefix timeout max_result_bytes credential
           credential_header credential_scheme credential_env gated trusted)
  @later ~w(cwd)

  @doc "Returns the servers `section` names, as `WardrikMCP` takes them, or the key that doesn't read."
  @spec read(map() | nil) :: {:ok, keyword()} | {:error, String.t()}
  def read(nil), do: {:ok, []}

  def read(section) when is_map(section) do
    servers = Enum.map(section, fn {name, server} -> {name, server(name, server)} end)

    case Enum.find(servers, &match?({_name, {:error, _why}}, &1)) do
      nil -> {:ok, for({name, {:ok, opts}} <- servers, do: {name, opts})}
      {name, {:error, why}} -> {:error, "mcp.#{name}#{why}"}
    end
  end

  def read(_section), do: {:error, "mcp: is a server for each name"}

  defp server(_name, server) when is_map(server) do
    with :ok <- known(server),
         :ok <- gated(server["gated"]),
         :ok <- trusted(server["trusted"]),
         {:ok, transport} <- transport(server) do
      {:ok, [transport: transport] ++ options(server)}
    end
  end

  defp server(_name, _server), do: {:error, ": is a server's keys, with a command or a url"}

  defp known(server) do
    case Enum.find(Map.keys(server), &(&1 not in @keys)) do
      nil -> :ok
      key when key in @later -> {:error, ".#{key}: isn't supported here yet"}
      key -> {:error, ".#{key}: isn't a key of a server"}
    end
  end

  defp transport(%{"url" => url, "command" => _command}) when is_binary(url),
    do: {:error, ": has a url or a command, not both"}

  defp transport(%{"url" => url} = server) when is_binary(url),
    do: {:ok, {:streamable_http, base_url: url, headers: Map.get(server, "headers", %{})}}

  defp transport(%{"command" => command} = server) when is_binary(command),
    do:
      {:ok,
       {:stdio,
        command: command, args: Map.get(server, "args", []), env: Map.get(server, "env", %{})}}

  defp transport(_server), do: {:error, ": has a command to run it, or a url to reach it at"}

  defp options(server) do
    [
      only: server["only"],
      except: server["except"],
      prefix: server["prefix"],
      timeout: milliseconds(server["timeout"]),
      max_result_bytes: server["max_result_bytes"],
      credential_name: server["credential"],
      credential_header: server["credential_header"],
      credential_scheme: server["credential_scheme"],
      credential_env: server["credential_env"],
      gated: server["gated"],
      trusted: server["trusted"]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp gated(nil), do: :ok
  defp gated(gated) when is_boolean(gated), do: :ok

  defp gated(names) when is_list(names) do
    if Enum.all?(names, &is_binary/1), do: :ok, else: gated(:not_names)
  end

  defp gated(_gated),
    do: {:error, ".gated: is true, false, or the server's tool names, as [create_*]"}

  defp trusted(nil), do: :ok
  defp trusted(trusted) when is_boolean(trusted), do: :ok
  defp trusted(_trusted), do: {:error, ".trusted: is true or false"}

  defp milliseconds(nil), do: nil
  defp milliseconds(seconds), do: :timer.seconds(seconds)
end

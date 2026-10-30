defmodule WardrikDaemon.CLI.Servers do
  @moduledoc """
  The commands on MCP servers an owner adds, and the accounts an owner connects.

  Each acts for the deployment's org, unless given `--org` or `--user`.
  """

  alias WardrikDaemon.CLI.Command
  alias WardrikDaemon.CLI.Context
  alias WardrikDaemon.CLI.Table

  @owner [org: :string, user: :string]

  @doc "Returns the commands on MCP servers and connections."
  @spec commands() :: [Command.t()]
  def commands do
    [
      %Command{
        name: "server ls",
        group: "MCP servers",
        switches: @owner,
        summary: "the MCP servers an owner added for their agents",
        run: &servers/3
      },
      %Command{
        name: "server add",
        group: "MCP servers",
        arguments: "NAME",
        switches:
          [url: :string, secret: :string, oauth: :boolean, scope: :keep, only: :string] ++ @owner,
        count: 1,
        summary: "add an MCP server at --url for an owner's agents",
        details: [
          "Its agents sign in with the owner's --secret NAME from the vault, with --oauth, asking",
          "for each --scope, or with nothing. --only names the tools they take, with commas.",
          "Agents reach it as NAME/* in their tools."
        ],
        run: &added/3
      },
      %Command{
        name: "server rm",
        group: "MCP servers",
        arguments: "NAME",
        switches: @owner,
        count: 1,
        summary: "remove an MCP server an owner added",
        run: &removed/3
      },
      %Command{
        name: "connection ls",
        group: "Connections",
        switches: @owner,
        summary: "the accounts an owner is offered, and which they hold",
        run: &connections/3
      },
      %Command{
        name: "connection connect",
        group: "Connections",
        arguments: "PROVIDER",
        switches: @owner,
        count: 1,
        summary: "sign an owner in to an account, for their agents to use",
        run: &connected/3
      },
      %Command{
        name: "connection disconnect",
        group: "Connections",
        arguments: "PROVIDER",
        switches: @owner,
        count: 1,
        summary: "forget an owner's account",
        run: &disconnected/3
      }
    ]
  end

  defp owner(cx, flags), do: Context.owner(cx, flags, cx.org)

  defp servers([], flags, cx) do
    with {:ok, %{"servers" => servers} = answer} <-
           Context.call(cx, "mcp_servers.list", %{"owner" => owner(cx, flags)}) do
      Table.show(
        cx,
        answer,
        ["SERVER", "URL", "SIGNS IN WITH"],
        for(server <- servers, do: [server["name"], server["url"], server["auth"]]),
        "No servers added."
      )
    end
  end

  defp added([name], %{url: url} = flags, cx) do
    input =
      %{"owner" => owner(cx, flags), "name" => name, "url" => url, "auth" => auth(flags)}
      |> Context.put("only", only(flags[:only]))

    with {:ok, answer} <- Context.call(cx, "mcp_servers.add", input),
         do: Context.done(cx, answer, "Added #{name}. Agents reach it as #{name}/*.")
  end

  defp added([_name], _flags, _cx), do: {:error, "Give the server's --url."}

  defp auth(%{secret: secret}), do: %{"secret" => %{"name" => secret}}
  defp auth(%{oauth: true} = flags), do: %{"oauth" => %{"scopes" => List.wrap(flags[:scope])}}
  defp auth(_flags), do: %{"none" => %{}}

  defp only(nil), do: nil
  defp only(tools), do: String.split(tools, ",", trim: true)

  defp removed([name], flags, cx) do
    input = %{"owner" => owner(cx, flags), "server" => name}

    with {:ok, answer} <- Context.call(cx, "mcp_servers.remove", input),
         do: Context.done(cx, answer, "Removed #{name}.")
  end

  defp connections([], flags, cx) do
    with {:ok, %{"connections" => connections} = answer} <-
           Context.call(cx, "connections.list", %{"owner" => owner(cx, flags)}) do
      Table.show(
        cx,
        answer,
        ["ACCOUNT", "CONNECTED"],
        for(
          connection <- connections,
          do: [connection["provider"], held(connection["connected"])]
        ),
        "No accounts are offered."
      )
    end
  end

  defp held(true), do: "yes"
  defp held(_connected), do: "no"

  defp connected([provider], flags, cx) do
    input = %{"owner" => owner(cx, flags), "provider" => provider}

    with {:ok, answer} <- Context.call(cx, "connections.connect", input) do
      Context.show(cx, answer, fn answer -> signing_in(cx, provider, answer) end)
    end
  end

  defp signing_in(cx, provider, %{"connected" => true}),
    do: Context.puts(cx, "#{provider} is connected already.")

  defp signing_in(cx, provider, %{"authorization" => %{"url" => url}}),
    do: Context.puts(cx, ["Sign in to #{provider} at ", Owl.Data.tag(url, :cyan)])

  defp disconnected([provider], flags, cx) do
    input = %{"owner" => owner(cx, flags), "provider" => provider}

    with {:ok, answer} <- Context.call(cx, "connections.disconnect", input),
         do: Context.done(cx, answer, "Disconnected #{provider}.")
  end
end

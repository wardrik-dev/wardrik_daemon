defmodule WardrikDaemon.CLI.Access do
  @moduledoc "The commands on tokens and the vault: who reaches the daemon, and the secrets agents hold."

  alias WardrikDaemon.CLI.Command
  alias WardrikDaemon.CLI.Context
  alias WardrikDaemon.CLI.Table

  @owner [org: :string, user: :string]

  @doc "Returns the commands on tokens and the vault."
  @spec commands() :: [Command.t()]
  def commands do
    [
      %Command{
        name: "token create",
        group: "Tokens",
        arguments: "NAME",
        switches: [resource: :keep, role: :string, expires: :string, policy: :string],
        count: 1,
        summary: "make a token for the HTTP API, and show its secret once",
        details: [
          "--resource names what it reaches, as acme/*, and may be given again. --role is a role,",
          "or several with commas: reader, messenger, approver, definer, worker or owner.",
          "--expires is how long it lasts, as 30d, 12h or 15m. --policy names a policy every",
          "agent it defines is held to."
        ],
        run: &created/3
      },
      %Command{
        name: "token ls",
        group: "Tokens",
        summary: "the tokens, and when each expires",
        run: &tokens/3
      },
      %Command{
        name: "token revoke",
        group: "Tokens",
        arguments: "ID",
        count: 1,
        summary: "stop a token working",
        run: &revoked/3
      },
      %Command{
        name: "vault put",
        group: "Vault",
        arguments: "NAME",
        switches: @owner,
        count: 1,
        summary: "seal a secret, read from stdin, for the deployment, an --org or a --user",
        details: ["echo \"$VALUE\" | wardrik vault put NAME"],
        run: &put/3
      },
      %Command{
        name: "vault ls",
        group: "Vault",
        switches: @owner,
        summary: "the names of the secrets held, never their values",
        run: &secrets/3
      },
      %Command{
        name: "vault rm",
        group: "Vault",
        arguments: "NAME",
        switches: @owner,
        count: 1,
        summary: "remove a secret",
        run: &removed/3
      }
    ]
  end

  defp created([name], flags, cx) do
    input =
      %{
        "name" => name,
        "resources" => flags |> Map.get(:resource, []) |> List.wrap(),
        "roles" => flags |> Map.get(:role, "") |> String.split(",", trim: true)
      }
      |> Context.put("policy", flags[:policy])
      |> Context.put("expires_in", seconds(flags[:expires]))

    with {:ok, %{"token" => token, "secret" => secret} = answer} <-
           Context.call(cx, "tokens.create", input) do
      Context.show(cx, answer, fn _answer ->
        Context.puts(
          cx,
          "#{token["id"]} expires #{token["expires"]}. Its secret, shown this once:"
        )

        Context.puts(cx, Owl.Data.tag(secret, :bright))
      end)
    end
  end

  defp tokens([], _flags, cx) do
    with {:ok, %{"tokens" => tokens} = answer} <- Context.call(cx, "tokens.list", %{}) do
      Table.show(
        cx,
        answer,
        ["TOKEN", "NAME", "EXPIRES"],
        for(token <- tokens, do: [token["id"], token["name"], token["expires"]]),
        "No tokens."
      )
    end
  end

  defp revoked([id], _flags, cx) do
    with {:ok, answer} <- Context.call(cx, "tokens.revoke", %{"token" => id}),
         do: Context.done(cx, answer, "Revoked #{id}.")
  end

  defp put([name], flags, cx) do
    case IO.gets("") do
      value when is_binary(value) and value != "\n" ->
        input = %{
          "owner" => Context.owner(cx, flags),
          "name" => name,
          "value" => String.trim_trailing(value, "\n")
        }

        with {:ok, answer} <- Context.call(cx, "secrets.put", input),
             do: Context.done(cx, answer, "Sealed #{name}.")

      _nothing ->
        {:error, "Give the value on stdin: echo \"$VALUE\" | #{cx.program} vault put #{name}"}
    end
  end

  defp secrets([], flags, cx) do
    with {:ok, %{"secrets" => secrets} = answer} <-
           Context.call(cx, "secrets.list", %{"owner" => Context.owner(cx, flags)}) do
      Table.show(
        cx,
        answer,
        ["SECRET", "KIND"],
        for(secret <- secrets, do: [secret["name"], secret["kind"]]),
        "No secrets."
      )
    end
  end

  defp removed([name], flags, cx) do
    input = %{"owner" => Context.owner(cx, flags), "name" => name}

    with {:ok, answer} <- Context.call(cx, "secrets.delete", input),
         do: Context.done(cx, answer, "Removed #{name}.")
  end

  defp seconds(nil), do: nil

  defp seconds(text) do
    case Integer.parse(text) do
      {n, "d"} -> n * 86_400
      {n, "h"} -> n * 3_600
      {n, "m"} -> n * 60
      {n, "s"} -> n
      _other -> nil
    end
  end
end

defmodule WardrikDaemon.CLI.Access do
  @moduledoc "The commands on who reaches the daemon and what agents reach: tokens and secrets."

  alias WardrikDaemon.CLI.Context
  alias WardrikDaemon.CLI.Table

  @doc "Runs the command `args` names."
  @spec run([String.t()], map(), Context.t()) :: :ok | :none | {:error, String.t()}
  def run(["token", "create", name], flags, cx) do
    input =
      %{
        "name" => name,
        "resources" => Map.get(flags, :resource, []) |> List.wrap(),
        "roles" => flags |> Map.get(:role, "") |> String.split(",", trim: true)
      }
      |> Context.put("policy", flags[:policy])
      |> Context.put("expires_in", seconds(flags[:expires]))

    with {:ok, %{"token" => token, "secret" => secret}} <-
           Context.call(cx, "tokens.create", input) do
      IO.puts("#{token["id"]} expires #{token["expires"]}. Its secret, shown this once:")
      IO.puts(secret)
    end
  end

  def run(["token", "list"], _flags, cx) do
    with {:ok, %{"tokens" => tokens}} <- Context.call(cx, "tokens.list", %{}),
         do: Table.print(for token <- tokens, do: [token["id"], token["name"], token["expires"]])
  end

  def run(["token", "revoke", id], _flags, cx) do
    with {:ok, _token} <- Context.call(cx, "tokens.revoke", %{"token" => id}),
         do: IO.puts("Revoked #{id}.")
  end

  def run(["vault", "put", name], flags, cx) do
    case IO.gets("") do
      value when is_binary(value) and value != "\n" ->
        input = %{
          "owner" => Context.owner(cx, flags),
          "name" => name,
          "value" => String.trim_trailing(value, "\n")
        }

        with {:ok, nil} <- Context.call(cx, "secrets.put", input), do: IO.puts("Sealed #{name}.")

      _nothing ->
        {:error, "Give the value on stdin: echo \"$VALUE\" | wardrik vault put #{name}"}
    end
  end

  def run(["vault", "ls"], flags, cx) do
    with {:ok, %{"secrets" => secrets}} <-
           Context.call(cx, "secrets.list", %{"owner" => Context.owner(cx, flags)}),
         do: Table.print(for secret <- secrets, do: [secret["name"], secret["kind"]])
  end

  def run(["vault", "rm", name], flags, cx) do
    with {:ok, nil} <-
           Context.call(cx, "secrets.delete", %{
             "owner" => Context.owner(cx, flags),
             "name" => name
           }),
         do: IO.puts("Removed #{name}.")
  end

  def run(_args, _flags, _cx), do: :none

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

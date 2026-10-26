defmodule WardrikDaemon.CLI.Admin do
  @moduledoc "The commands on the deployment: reloading it, where it runs, its audit, and checking it."

  alias WardrikDaemon.CLI.Context
  alias WardrikDaemon.CLI.Table
  alias WardrikDaemon.Client

  @doc "Runs the command `args` names."
  @spec run([String.t()], map(), Context.t()) :: :ok | :none | {:error, String.t()}
  def run(["reload"], _flags, cx) do
    with {:ok, %{"reloaded" => nodes}} <- Context.call(cx, "deployment.reload", %{}),
         do: IO.puts("Read the agent files again on #{Enum.join(nodes, ", ")}.")
  end

  def run(["status"], _flags, cx) do
    with {:ok, client} <- Context.client(cx),
         {:ok, %{"nodes" => nodes, "asleep" => asleep}} <-
           Context.called(Client.run(client, "deployment.nodes", %{})) do
      IO.puts("Wardrik runs at #{client.url}.")
      Table.print(for node <- nodes, do: [node["name"], "#{node["agents"]} agents"])
      IO.puts("#{asleep} asleep")
    end
  end

  def run(["audit"], _flags, cx) do
    with {:ok, %{"events" => events}} <- Context.call(cx, "audit.list", %{}) do
      Table.print(
        for event <- events,
            do: [event["time"], event["type"], get_in(event, ["data", "actor", "id"])]
      )
    end
  end

  def run(["doctor"], _flags, cx) do
    case cx.env |> WardrikDaemon.Doctor.run() |> WardrikDaemon.Doctor.print() do
      0 -> :ok
      failed -> {:error, "#{failed} of the checks failed."}
    end
  end

  def run(_args, _flags, _cx), do: :none
end

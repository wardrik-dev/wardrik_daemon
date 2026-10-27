defmodule WardrikDaemon.CLI.Admin do
  @moduledoc "The commands that set Wardrik up and run the daemon: init, doctor, status, reload, audit and the rest."

  alias WardrikDaemon.CLI.Command
  alias WardrikDaemon.CLI.Context
  alias WardrikDaemon.CLI.Init
  alias WardrikDaemon.CLI.Table
  alias WardrikDaemon.Client

  @doc "Returns the commands that set Wardrik up and run the daemon."
  @spec commands() :: [Command.t()]
  def commands do
    [
      %Command{
        name: "init",
        group: "Set up",
        switches: [org: :string, model: :string],
        summary: "write config.yaml and the front door, keeping what's there",
        run: &init/3
      },
      %Command{
        name: "doctor",
        group: "Set up",
        summary: "check what the daemon reads, running or not",
        run: &doctor/3
      },
      %Command{name: "version", group: "Set up", summary: "print the version", run: &version/3},
      script("daemon serve", "run the daemon here, logging to the terminal"),
      script("daemon start", "run the daemon in the background"),
      script("daemon stop", "stop the daemon"),
      script("daemon logs", "follow what the daemon logs"),
      script("daemon service install", "run the daemon as a systemd user service"),
      script("daemon service uninstall", "stop running it as a service"),
      %Command{
        name: "daemon status",
        group: "Daemon",
        summary: "where the daemon runs, and how many agents each node holds",
        run: &status/3
      },
      %Command{
        name: "daemon reload",
        group: "Daemon",
        summary: "read the agent files again, on every node",
        details: ["The doctor says which files don't read."],
        run: &reload/3
      },
      %Command{
        name: "daemon audit",
        group: "Daemon",
        summary: "what people changed, oldest first",
        run: &audit/3
      }
    ]
  end

  defp script(name, summary), do: %Command{name: name, group: "Daemon", summary: summary}

  defp init([], flags, cx) do
    model = Map.get(flags, :model, "anthropic:claude-haiku-4-5")

    for {path, done} <- Init.run(cx.dirs, Map.get(flags, :org, "default"), model),
        do: Context.puts(cx, [written(done), " ", path])

    :ok
  end

  defp written(:written), do: Owl.Data.tag("Wrote", :green)
  defp written(_kept), do: Owl.Data.tag("Kept ", :light_black)

  defp doctor([], _flags, cx) do
    case cx.env |> WardrikDaemon.Doctor.run() |> WardrikDaemon.Doctor.print() do
      0 -> :ok
      failed -> {:error, "#{failed} of the checks failed."}
    end
  end

  defp version([], _flags, cx),
    do: Context.puts(cx, "wardrik #{Application.spec(:wardrik_daemon, :vsn)}")

  defp status([], _flags, cx) do
    with {:ok, client} <- Context.client(cx),
         {:ok, %{"nodes" => nodes, "asleep" => asleep} = answer} <-
           Context.called(Client.run(client, "deployment.nodes", %{})),
         do: Context.show(cx, answer, fn _answer -> nodes(cx, client.url, nodes, asleep) end)
  end

  defp nodes(cx, url, nodes, asleep) do
    Context.puts(cx, ["Wardrik runs at ", Owl.Data.tag(url, :cyan), "."])
    rows = for node <- nodes, do: [node["name"], node["agents"]]
    Table.print(cx, ["NODE", "AGENTS"], rows, "No nodes answer.")
    Context.puts(cx, Owl.Data.tag("#{asleep} asleep", :light_black))
  end

  defp reload([], _flags, cx) do
    with {:ok, %{"reloaded" => nodes} = answer} <- Context.call(cx, "deployment.reload", %{}),
         do: Context.done(cx, answer, "Read the agent files again on #{Enum.join(nodes, ", ")}.")
  end

  defp audit([], _flags, cx) do
    with {:ok, %{"events" => events} = answer} <- Context.call(cx, "audit.list", %{}) do
      Table.show(
        cx,
        answer,
        ["WHEN", "WHAT", "WHO", "ON"],
        for(event <- events, do: change(event)),
        "Nothing has changed yet."
      )
    end
  end

  defp change(event),
    do: [event["time"], event["type"], get_in(event, ["data", "actor", "id"]), event["subject"]]
end

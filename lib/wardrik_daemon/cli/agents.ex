defmodule WardrikDaemon.CLI.Agents do
  @moduledoc "The commands on agents: listing and showing them, their triggers, and deciding what they wait on."

  alias WardrikDaemon.CLI.Context
  alias WardrikDaemon.CLI.Table

  @doc "Runs the command `args` names."
  @spec run([String.t()], map(), Context.t()) :: :ok | :none | {:error, String.t()}
  def run(["ls"], _flags, cx) do
    with {:ok, %{"agents" => agents}} <- Context.call(cx, "agents.list", %{}) do
      Table.print(for agent <- agents, do: [agent["id"], agent["status"]])
    end
  end

  def run(["show", agent], _flags, cx) do
    id = Context.agent(cx, agent)

    with {:ok, read} <- Context.call(cx, "agent.read", %{"agent" => id}),
         {:ok, %{"definition" => definition, "missing" => missing}} <-
           Context.call(cx, "agent.definition", %{"agent" => id}) do
      Table.print([
        ["id", id],
        ["status", read["status"]],
        ["description", definition["description"]],
        ["model", definition["model"]],
        ["tools", Enum.join(Map.get(definition, "tools", []), ", ")],
        ["policy", policy(definition["policy"])],
        ["waiting on", Enum.map_join(read["interrupts"], ", ", & &1["id"])],
        ["missing", Enum.join(missing, ", ")]
      ])
    end
  end

  def run(["triggers", agent], _flags, cx) do
    with {:ok, %{"definition" => definition}} <-
           Context.call(cx, "agent.definition", %{"agent" => Context.agent(cx, agent)}) do
      Table.print(
        for trigger <- Map.get(definition, "triggers", []),
            do: [trigger["name"], when_it_runs(trigger), trigger["prompt"]]
      )
    end
  end

  def run(["parked"], _flags, cx) do
    with {:ok, %{"interrupts" => listed}} <- Context.call(cx, "interrupts.list", %{}) do
      Table.print(
        for %{"agent" => %{"id" => agent}, "interrupt" => interrupt} <- listed,
            do: [agent, interrupt["id"], interrupt["name"] || "the model", interrupt["message"]]
      )
    end
  end

  def run(["approve", agent, call], flags, cx) do
    input =
      Context.put(
        %{"agent" => Context.agent(cx, agent), "interrupt" => call},
        "note",
        flags[:note]
      )

    with {:ok, _decided} <- Context.call(cx, "agent.approve", input),
         do: IO.puts("Approved #{call}.")
  end

  def run(["deny", agent, call], flags, cx) do
    input =
      Context.put(
        %{"agent" => Context.agent(cx, agent), "interrupt" => call},
        "reason",
        flags[:reason]
      )

    with {:ok, _decided} <- Context.call(cx, "agent.deny", input), do: IO.puts("Denied #{call}.")
  end

  def run(["history", agent], _flags, cx) do
    with {:ok, %{"items" => items}} <-
           Context.call(cx, "agent.timeline", %{"agent" => Context.agent(cx, agent)}),
         do: Enum.each(items, &IO.puts(said(&1)))
  end

  def run(["agent", "rm", agent], _flags, cx) do
    id = Context.agent(cx, agent)

    with {:ok, nil} <- Context.call(cx, "agent.forget", %{"agent" => id}),
         do: IO.puts("Removed #{id}.")
  end

  def run(_args, _flags, _cx), do: :none

  defp said(%{"kind" => "user", "sender" => sender} = item) when is_binary(sender),
    do: "> #{sender}: #{item["text"]}"

  defp said(%{"kind" => "user"} = item), do: "> #{item["text"]}"

  defp said(%{"kind" => "run", "status" => status, "steps" => steps}),
    do:
      Enum.map_join(steps, "\n", &step/1) <>
        if(status == "completed", do: "", else: "\n[#{status}]")

  defp said(_item), do: ""

  defp step(%{"type" => "text", "text" => text}), do: text

  defp step(%{"type" => "tool", "name" => name, "status" => status}),
    do: "  → #{name} (#{status})"

  defp step(_step), do: ""

  defp policy(nil), do: nil
  defp policy(name) when is_binary(name), do: name
  defp policy(_rules), do: "its own rules"

  defp when_it_runs(%{"every" => every}), do: "every #{every}"
  defp when_it_runs(%{"feed" => feed}), do: "on #{feed["url"]}"
  defp when_it_runs(%{"webhook" => _webhook}), do: "on a webhook"
  defp when_it_runs(_trigger), do: ""
end

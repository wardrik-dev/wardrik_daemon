defmodule WardrikDaemon.CLI.Approvals do
  @moduledoc "The commands on what agents wait on a person for: listing, approving and denying it."

  alias WardrikDaemon.CLI.Command
  alias WardrikDaemon.CLI.Context
  alias WardrikDaemon.CLI.Table

  @group "Approvals"

  @doc "Returns the commands on approvals."
  @spec commands() :: [Command.t()]
  def commands do
    [
      %Command{
        name: "approval ls",
        group: @group,
        summary: "the calls agents wait on a person for",
        details: ["A call held because its run read content from outside says so."],
        run: &listed/3
      },
      %Command{
        name: "approval approve",
        group: @group,
        arguments: "AGENT CALL",
        switches: [note: :string],
        count: 2,
        summary: "let a call run; a --note reaches the model beside its result",
        run: &decided(&1, &2, &3, "agent.approve", :note, "Approved")
      },
      %Command{
        name: "approval deny",
        group: @group,
        arguments: "AGENT CALL",
        switches: [reason: :string],
        count: 2,
        summary: "refuse a call; a --reason reaches the model as its error",
        run: &decided(&1, &2, &3, "agent.deny", :reason, "Denied")
      }
    ]
  end

  defp listed([], _flags, cx) do
    with {:ok, %{"interrupts" => listed} = answer} <- Context.call(cx, "interrupts.list", %{}) do
      Table.show(
        cx,
        answer,
        ["AGENT", "CALL", "TOOL", "WHY"],
        for(
          %{"agent" => %{"id" => agent}, "interrupt" => interrupt} <- listed,
          do: row(agent, interrupt)
        ),
        "Nothing waits on a person."
      )
    end
  end

  defp row(agent, interrupt),
    do: [agent, interrupt["id"], interrupt["name"] || "the model", why(interrupt)]

  defp why(%{"labels" => [_label | _labels], "message" => message}),
    do: message <> " [after content from outside]"

  defp why(interrupt), do: interrupt["message"]

  defp decided([agent, call], flags, cx, operation, given, done) do
    decision = %{"agent" => Context.agent(cx, agent), "interrupt" => call}
    input = Context.put(decision, Atom.to_string(given), flags[given])

    with {:ok, answer} <- Context.call(cx, operation, input),
         do: Context.done(cx, answer, "#{done} #{call}.")
  end
end

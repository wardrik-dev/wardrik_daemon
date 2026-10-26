defmodule WardrikDaemon.CLI.Ask do
  @moduledoc """
  Asks an agent something, and writes its answer as it comes. Where the agent waits on a person, it
  says which calls, and how to approve them.
  """

  alias WardrikDaemon.Client

  @timeout :timer.minutes(10)

  @doc "Asks `agent` what `text` says, as the client's token, and writes what it answers to stdout."
  @spec run(Client.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def run(client, agent, text) do
    with {:ok, stream} <- open(client, agent),
         {:ok, %{"message" => %{"id" => id}}} <- asked(client, agent, text, stream) do
      follow(stream, %{agent: agent, message: id, run: nil, written?: false})
    end
  end

  defp open(client, agent) do
    case Client.open(client, "agent.events", %{"agent" => agent}) do
      {:ok, stream} -> {:ok, stream}
      {:error, _type, message} -> {:error, message}
    end
  end

  defp asked(client, agent, text, stream) do
    case Client.run(client, "agent.ask", %{"agent" => agent, "content" => text}) do
      {:ok, asked} ->
        {:ok, asked}

      {:error, _type, message} ->
        Client.close(stream)
        {:error, message}
    end
  end

  defp follow(stream, state) do
    case Client.next(stream, @timeout) do
      {:ok, events, stream} ->
        followed(stream, seen(events, state))

      :done ->
        {:error, "The daemon stopped the answer before it ended."}

      :timeout ->
        stopped(stream, {:error, "Nothing came for ten minutes, so it stopped waiting."})
    end
  end

  defp followed(stream, {:ended, outcome}), do: stopped(stream, outcome)
  defp followed(stream, state), do: follow(stream, state)

  defp stopped(stream, outcome) do
    Client.close(stream)
    outcome
  end

  defp seen([], state), do: state

  defp seen([event | events], state) do
    case step(event, state) do
      {:ended, outcome} -> {:ended, outcome}
      state -> seen(events, state)
    end
  end

  defp step(%{"type" => "wardrik.run.started", "data" => %{"run" => run}}, %{run: nil} = state) do
    if state.message in Map.get(run, "message_ids", []),
      do: %{state | run: run["id"]},
      else: state
  end

  defp step(event, %{run: run} = state) when is_binary(run) do
    if trace(event) == run, do: ours(event, state), else: state
  end

  defp step(_event, state), do: state

  defp ours(%{"type" => "wardrik.message.delta", "data" => %{"delta" => text}}, state) do
    IO.write(text)
    %{state | written?: true}
  end

  defp ours(%{"type" => "wardrik.run.completed", "data" => data}, state) do
    unless state.written?, do: IO.write(last_said(data["messages"]))
    IO.write("\n")
    {:ended, :ok}
  end

  defp ours(
         %{"type" => "wardrik.run.interrupted", "data" => %{"interrupts" => interrupts}},
         state
       ) do
    IO.write("\n")
    Enum.each(interrupts, &waiting(&1, state.agent))
    {:ended, :ok}
  end

  defp ours(%{"type" => "wardrik.run.failed", "data" => %{"error" => error}}, _state),
    do: {:ended, {:error, "It failed: #{error["message"]}"}}

  defp ours(%{"type" => "wardrik.run.cancelled"}, _state),
    do: {:ended, {:error, "It was stopped before it answered."}}

  defp ours(_event, state), do: state

  defp waiting(%{"id" => id} = interrupt, agent) do
    IO.puts(
      "Waiting on a person for #{interrupt["name"] || "the model"}: #{interrupt["message"]}"
    )

    IO.puts("  wardrik approve #{agent} #{id}")
    IO.puts("  wardrik deny #{agent} #{id}")
  end

  defp last_said(messages) do
    messages
    |> Enum.filter(&(&1["role"] == "assistant"))
    |> Enum.flat_map(&Map.get(&1, "parts", []))
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join(& &1["content"])
  end

  defp trace(%{"traceparent" => "00-" <> rest}), do: rest |> String.split("-", parts: 2) |> hd()
  defp trace(_event), do: nil
end

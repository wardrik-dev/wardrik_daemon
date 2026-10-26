defmodule WardrikDaemon.CLITest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureIO
  import WardrikDaemon.Test

  alias WardrikDaemon.CLI

  setup :set_mimic_global

  setup context do
    context = dirs(context)

    write(context, "config.yaml", """
    org: acme
    http: {port: #{free_port()}}
    defaults: {model: #{model()}}
    """)

    write(context, "policies/careful.yaml", "ask: [echo]\n")

    write(context, "agents/triage.md", """
    ---
    description: Triages.
    tools: [echo]
    policy: careful
    triggers:
      - {name: daily, every: "0 9 * * *", prompt: Go.}
    ---
    You watch the queue.
    """)

    context
  end

  defp wardrik(context, argv, input \\ "") do
    output =
      capture_io(input, fn -> send(self(), {:status, CLI.main(argv, env: context.env)}) end)

    assert_received {:status, status}
    {status, output}
  end

  defp failing(context, argv) do
    run = fn -> send(self(), {:status, CLI.main(argv, env: context.env)}) end
    stderr = capture_io(:stderr, fn -> capture_io("", run) end)

    assert_received {:status, 1}
    stderr
  end

  test "writes a first config and agent, and keeps what's there", context do
    File.rm!(Path.join(context.env["WARDRIK_CONFIG_DIR"], "config.yaml"))

    assert {0, output} = wardrik(context, ["init", "--org", "globex"])
    assert output =~ "Wrote " <> Path.join(context.env["WARDRIK_CONFIG_DIR"], "config.yaml")
    assert output =~ "agents/assistant.md"

    assert File.read!(Path.join(context.env["WARDRIK_CONFIG_DIR"], "config.yaml")) =~
             "org: globex"

    assert {0, again} = wardrik(context, ["init"])
    assert again =~ "Kept"
  end

  test "writes a front door that the daemon defines", context do
    assert {0, _wrote} = wardrik(context, ["init"])
    context = start_daemon(context)

    assert {:ok, %Wardrik.Definition{} = front, []} =
             Wardrik.Agent.definition(context.owner, "acme/assistant")

    assert front.tools == ["self/*", "agents/*", "files", "web_search", "run_lua"]
    assert front.context == ["MEMORY.md"]
    assert front.idle_timeout == :infinity
    assert front.policy == %{"budget" => %{"tokens" => 2_000_000, "per" => "day"}}
    assert front.instructions =~ "You are Wardrik, the one place the people of this org come"
    assert front.instructions =~ "# Playbook"
  end

  test "says how to start the daemon where it hasn't", context do
    assert failing(context, ["ls"]) =~ "Start it with `wardrik start`"
    assert failing(context, ["nope"]) =~ "nope isn't a command"
    assert failing(context, ["ls", "--colour", "red"]) =~ "--colour isn't an option"
    assert {0, help} = wardrik(context, ["help"])
    assert help =~ "Usage: wardrik COMMAND"
  end

  describe "with the daemon running" do
    setup :start_daemon

    test "lists and shows agents, and their triggers", context do
      assert {0, listed} = wardrik(context, ["ls"])
      assert listed =~ ~r/acme\/triage\s+idle/

      assert {0, shown} = wardrik(context, ["show", "triage"])
      assert shown =~ ~r/description\s+Triages\./
      assert shown =~ ~r/policy\s+careful/

      assert {0, triggers} = wardrik(context, ["triggers", "acme/triage"])
      assert triggers =~ ~r/daily\s+every 0 9 \* \* \*\s+Go\./

      assert failing(context, ["show", "nobody"]) =~ "acme/nobody"
      assert failing(context, ["agent", "rm", "triage"]) =~ "declared by a file"
    end

    test "asks an agent, and says what it waits on", context do
      answers([answer("Two cases.")])
      assert {0, "Two cases.\n"} = wardrik(context, ["ask", "triage", "How", "many?"])
      assert {0, history} = wardrik(context, ["history", "triage"])
      assert history =~ "> How many?"
      assert history =~ "Two cases."

      answers([calling("call_1", "echo", %{"text" => "hi"}), answer("Done.")])
      assert {0, waiting} = wardrik(context, ["ask", "triage", "Echo hi"])
      assert waiting =~ "Waiting on a person for echo"
      assert waiting =~ "wardrik approve acme/triage call_1"

      assert {0, parked} = wardrik(context, ["parked"])
      assert parked =~ ~r/acme\/triage\s+call_1\s+echo/

      assert {0, "Approved call_1.\n"} =
               wardrik(context, ["approve", "triage", "call_1", "--note", "Go."])

      assert failing(context, ["deny", "triage", "call_1"]) =~ "doesn't wait on call_1"
    end

    test "says why an answer failed", context do
      Mimic.stub(ReqLLM, :stream_text, fn _model, _messages, _opts ->
        {:error, %RuntimeError{message: "down"}}
      end)

      assert failing(context, ["ask", "triage", "Hi"]) =~ "It failed"
    end

    test "makes, lists and revokes tokens", context do
      assert {0, made} =
               wardrik(context, [
                 "token",
                 "create",
                 "ci",
                 "--resource",
                 "acme/agent/*",
                 "--role",
                 "reader,messenger",
                 "--expires",
                 "30d"
               ])

      assert made =~ "shown this once"
      [id | _rest] = String.split(made)

      assert {0, listed} = wardrik(context, ["token", "list"])
      assert listed =~ "ci"
      assert {0, "Revoked " <> _rest} = wardrik(context, ["token", "revoke", id])
    end

    test "seals, lists and removes secrets", context do
      assert {0, "Sealed GITHUB_TOKEN.\n"} =
               wardrik(context, ["vault", "put", "GITHUB_TOKEN", "--org", "acme"], "ghp_1\n")

      assert {:ok, "ghp_1"} = Wardrik.fetch_secret(context.wardrik, "acme", "GITHUB_TOKEN")

      assert {0, "Sealed MINE.\n"} =
               wardrik(context, ["vault", "put", "MINE", "--user", "jon"], "x\n")

      assert {0, "Sealed DEPLOY.\n"} = wardrik(context, ["vault", "put", "DEPLOY"], "d\n")
      assert failing(context, ["vault", "put", "EMPTY"]) =~ "Give the value on stdin"

      assert {0, listed} = wardrik(context, ["vault", "ls", "--org", "acme"])
      assert listed =~ ~r/GITHUB_TOKEN\s+secret/

      assert {0, "Removed GITHUB_TOKEN.\n"} =
               wardrik(context, ["vault", "rm", "GITHUB_TOKEN", "--org", "acme"])
    end

    test "reloads, says where it runs, and lists what people changed", context do
      assert {0, "Read the agent files again on " <> _nodes} = wardrik(context, ["reload"])
      assert {0, status} = wardrik(context, ["status"])
      assert status =~ "Wardrik runs at http://127.0.0.1:"
      assert {0, audit} = wardrik(context, ["audit"])
      assert audit =~ "wardrik.agent.defined"
    end

    test "reaches another daemon by its URL and token", context do
      {:ok, %{url: url, secret: secret}} =
        WardrikDaemon.CLIToken.read(Path.join(context.env["WARDRIK_DATA_HOME"], "cli_token"))

      remote =
        Map.merge(context.env, %{
          "WARDRIK_URL" => url,
          "WARDRIK_TOKEN" => secret,
          "WARDRIK_DATA_HOME" => "/nowhere"
        })

      assert {0, listed} = wardrik(%{context | env: remote}, ["ls"])
      assert listed =~ "acme/triage"
    end
  end

  defp answers(responses) do
    {:ok, queue} = Agent.start_link(fn -> responses end)
    Mimic.stub(ReqLLM.StreamResponse, :process_stream, fn response, _opts -> {:ok, response} end)

    Mimic.stub(ReqLLM, :stream_text, fn _model, _messages, _opts ->
      {:ok, Agent.get_and_update(queue, fn [next | rest] -> {next, rest} end)}
    end)
  end

  defp answer(text), do: response(ReqLLM.Context.assistant(text))

  defp calling(id, name, args),
    do:
      response(
        ReqLLM.Context.assistant("",
          tool_calls: [ReqLLM.ToolCall.new(id, name, JSON.encode!(args))]
        )
      )

  defp response(message),
    do: %ReqLLM.Response{id: "resp", model: "test", context: nil, message: message}
end

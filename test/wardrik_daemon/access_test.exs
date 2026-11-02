defmodule WardrikDaemon.AccessTest do
  use ExUnit.Case, async: false

  import WardrikDaemon.Test

  alias WardrikDaemon.Client
  alias WardrikDaemon.Tokens

  setup context do
    context = dirs(context)
    port = free_port()

    write(context, "config.yaml", """
    org: payments
    orgs: {growth: {}}
    http: {port: #{port}}
    defaults: {model: #{model()}}
    roles:
      reader: {rules: [{verbs: [read, events], kinds: [agent]}]}
    bindings:
      - {org: payments, role: operator, subjects: [user:ana, user:payments/@ana]}
      - {org: payments, role: reader, subjects: [agent:payments/@ana/helper]}
    """)

    write(context, "agents/triage.md", "---\ndescription: Triages.\n---\nYou triage.\n")
    context = start_daemon(context)
    {:ok, _agent} = Wardrik.Agent.define(context.admin, "growth/triage", model: model())
    Map.put(context, :url, "http://127.0.0.1:#{port}")
  end

  defp client(context, subject) do
    {:ok, %{secret: secret}} =
      Tokens.create(context.daemon_store,
        name: "test",
        subject: subject,
        expires: DateTime.add(DateTime.utc_now(), 1, :hour)
      )

    %Client{url: context.url, secret: secret}
  end

  test "a user bound in one org reaches nothing in another, nor the deployment", context do
    ana = client(context, "user:ana")

    assert {:ok, _agent} = Client.run(ana, "agent.read", %{"agent" => "payments/triage"})

    assert {:error, "not_found", _message} =
             Client.run(ana, "agent.read", %{"agent" => "growth/triage"})

    assert {:error, "not_found", _message} =
             Client.run(ana, "agent.forget", %{"agent" => "growth/triage"})

    assert {:error, "not_found", _message} = Client.run(ana, "deployment.reload", %{})
    assert {:ok, %{"agents" => agents}} = Client.run(ana, "agents.list", %{})
    assert for(agent <- agents, do: agent["id"]) == ["payments/triage"]

    admin = %Client{ana | secret: "wdk_nope_nope"}
    assert {:error, "unauthorized", _message} = Client.run(admin, "agents.list", %{})
  end

  test "an agent gets its own role, not its owner's", context do
    owner = Wardrik.as(context.wardrik, "payments/@ana")
    agent = Wardrik.as(context.wardrik, "payments/@ana", actor: {:agent, "payments/@ana/helper"})
    defined = %{"agent" => "payments/other", "model" => model()}

    assert {:ok, _definition, _problems} = Wardrik.Agent.definition(agent, "payments/triage")

    for {action, input} <- [
          {"agent.define", defined},
          {"agent.ask", %{"agent" => "payments/triage", "content" => "Hi"}},
          {"agent.define", %{defined | "agent" => "payments/@ana/notes"}}
        ] do
      assert {:error, %Wardrik.Error{type: :forbidden}} = Wardrik.run(agent, action, input)
    end

    assert {:ok, _snapshot} = Wardrik.run(owner, "agent.define", defined)

    helper = client(context, "agent:payments/@ana/helper")

    assert {:error, "forbidden", _message} =
             Client.run(helper, "agent.define", %{defined | "agent" => "payments/more"})

    assert {:ok, _agent} = Client.run(helper, "agent.read", %{"agent" => "payments/triage"})
  end
end

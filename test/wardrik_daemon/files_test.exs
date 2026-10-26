defmodule WardrikDaemon.FilesTest do
  use ExUnit.Case, async: true

  import WardrikDaemon.Test

  alias WardrikDaemon.AgentFile
  alias WardrikDaemon.Config
  alias WardrikDaemon.EnvFile
  alias WardrikDaemon.Policies

  setup context, do: dirs(context)

  @config %Config{
    org: "acme",
    defaults: %{"model" => "anthropic:claude-haiku-4-5", "timeout" => 60}
  }

  test "reads an agent's file into its ID and definition, over the defaults", context do
    path =
      write(context, "agents/triage.md", """
      ---
      description: Triages.
      timeout: 120
      ---
      You watch the queue.
      """)

    assert AgentFile.read(path, @config) ==
             {:ok, "acme/triage",
              %{
                "description" => "Triages.",
                "model" => "anthropic:claude-haiku-4-5",
                "timeout" => 120,
                "instructions" => "You watch the queue."
              }}
  end

  test "names the agent by its file, or as it says, for its user", context do
    plain = write(context, "agents/plain.md", "Be brief.")
    assert {:ok, "acme/plain", %{"instructions" => "Be brief."}} = AgentFile.read(plain, @config)

    named = write(context, "agents/x.md", "---\nname: notes\nuser: \"@jon\"\n---\n")
    assert {:ok, "acme/@jon/notes", definition} = AgentFile.read(named, @config)
    refute Map.has_key?(definition, "instructions")
  end

  test "says why a file doesn't read", context do
    refused = [
      {"---\norg: globex\n---\n", "is in the org globex"},
      {"---\nmodel: x\n", "never closes it"},
      {"---\n- a\n---\n", "isn't a set of keys"},
      {"---\na: [\n---\n", "isn't YAML"}
    ]

    for {text, why} <- refused do
      path = write(context, "agents/bad.md", text)
      assert {:error, message} = AgentFile.read(path, @config)
      assert message =~ why
    end

    assert {:error, message} = AgentFile.read(Path.join(context.root, "none.md"), @config)
    assert message =~ "no such file"
  end

  test "reads each policy by its file's name", context do
    write(context, "policies/careful.yaml", "ask: [echo]\n")
    write(context, "policies/open.yml", "default: allow\n")

    assert {:ok, %{"careful" => %WardrikPolicy{}, "open" => %WardrikPolicy{}}} =
             Policies.read(Path.join(context.env["WARDRIK_CONFIG_DIR"], "policies"))

    write(context, "policies/empty.yaml", "")

    assert {:error, message} =
             Policies.read(Path.join(context.env["WARDRIK_CONFIG_DIR"], "policies"))

    assert message =~ "empty.yaml: is empty"

    File.rm!(Path.join(context.env["WARDRIK_CONFIG_DIR"], "policies/empty.yaml"))
    write(context, "policies/odd.yaml", "colour: red\n")

    assert {:error, _why} =
             Policies.read(Path.join(context.env["WARDRIK_CONFIG_DIR"], "policies"))

    File.rm!(Path.join(context.env["WARDRIK_CONFIG_DIR"], "policies/odd.yaml"))
    write(context, "policies/broken.yaml", "a: [\n")

    assert {:error, message} =
             Policies.read(Path.join(context.env["WARDRIK_CONFIG_DIR"], "policies"))

    assert message =~ "isn't YAML"
  end

  test "sets what the env file says where the environment doesn't", context do
    path =
      write(context, "env", """
      # keys
      export ANTHROPIC_API_KEY="sk-ant"
      SLACK_BOT_TOKEN='xoxb'
      HOME=/elsewhere
      not a variable
      9BAD=1
      """)

    assert EnvFile.load(path, %{"HOME" => "/home/me"}) == %{
             "ANTHROPIC_API_KEY" => "sk-ant",
             "SLACK_BOT_TOKEN" => "xoxb",
             "HOME" => "/home/me"
           }

    assert EnvFile.load(Path.join(context.root, "none"), %{"A" => "1"}) == %{"A" => "1"}
  end
end

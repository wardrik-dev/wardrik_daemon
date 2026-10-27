defmodule WardrikDaemon.ConfigTest do
  use ExUnit.Case, async: true

  import WardrikDaemon.Test

  alias WardrikDaemon.Config
  alias WardrikDaemon.Dirs

  setup context, do: dirs(context)

  defp read(context, text, env \\ %{}) do
    write(context, "config.yaml", text)
    Config.read(Dirs.new(context.env), Map.merge(context.env, env))
  end

  test "reads as the defaults where there's no config.yaml", %{env: env} do
    assert {:ok, %Config{org: "default", port: 4747, ip: {127, 0, 0, 1}, mcp: [], channels: []}} =
             Config.read(Dirs.new(env), env)
  end

  test "reads what agents reach, with ${NAME} from the environment", context do
    yaml = """
    org: acme
    base_url: https://agents.acme.test/
    defaults: {model: anthropic:claude-haiku-4-5}
    http: {port: 4000, ip: 0.0.0.0}
    vault: {keys: ["${KEY}"]}
    mcp:
      github:
        url: https://api.githubcopilot.com/mcp/
        credential: github
        only: [list_commits]
        timeout: 30
      notes:
        command: npx
        args: [-y, notes]
    oauth:
      providers:
        github: {issuer: https://github.com/login/oauth, client_id: "${GITHUB_CLIENT_ID}", scopes: [repo], flow: device}
    channels:
      slack: {type: slack, token: xoxb-1, app_token: xapp-1, approvers: ["@maria"]}
      ops: {type: slack, signing_secret: s, client_id: "1.2", client_secret: c, approvers: anyone}
    brave: {api_key: "${KEY}"}
    models:
      zai_coding_plan:glm-5.1: {priced_as: zai:glm-5.1, markup: 0.1}
      openrouter:x: {input: 0.6, output: 2.2}
    cluster: {}
    """

    assert {:ok, config} = read(context, yaml, %{"KEY" => "k3y", "GITHUB_CLIENT_ID" => "Iv1"})

    assert %Config{org: "acme", port: 4000, keys: ["k3y"], defaults: %{"model" => _model}} =
             config

    assert Config.url(config) == "http://127.0.0.1:4000"
    assert Config.base_url(config) == "https://agents.acme.test"

    assert [
             {"github",
              [
                transport:
                  {:streamable_http, base_url: "https://api.githubcopilot.com/mcp/", headers: %{}}
              ] ++ github},
             {"notes", [transport: {:stdio, command: "npx", args: ["-y", "notes"], env: %{}}]}
           ] = config.mcp

    assert github == [only: ["list_commits"], timeout: 30_000, credential_name: "github"]
    assert [{"github", provider}] = config.oauth
    assert provider[:flow] == :device
    assert provider[:client_id] == "Iv1"

    assert [{"ops", {WardrikSlack, ops}}, {"slack", {WardrikSlack, slack}}] =
             Enum.sort(config.channels)

    assert slack == [token: "xoxb-1", owner: "acme", approvers: ["@maria"], app_token: "xapp-1"]
    assert ops[:installations] == :stored
    assert ops[:approvers] == :anyone
    assert config.brave == "k3y"

    assert config.prices == %{
             "zai_coding_plan:glm-5.1" => [markup: 0.1, priced_as: "zai:glm-5.1"],
             "openrouter:x" => [input: 0.6, output: 2.2]
           }

    assert config.warnings == ["cluster isn't supported here yet, so it's passed over"]
  end

  test "reads where everything is kept, from the environment alone", context do
    write(context, "config.yaml", "storage: {postgres: {url: \"${DATABASE}\"}}\n")
    env = Map.put(context.env, "DATABASE", "postgres://u:p@db/wardrik")
    dirs = Dirs.new(env)

    assert {:ok, %{storage: {:postgres, "postgres://u:p@db/wardrik"}}} =
             Config.bootstrap(dirs, env)

    assert {:ok, %Config{storage: {:postgres, _url}}} = Config.read(dirs, env)

    assert {:ok, %Config{storage: nil}} = read(context, "org: acme\n")
    assert {:error, why} = read(context, "storage: {s3: {bucket: b}}\n")
    assert why =~ "storage.s3: isn't supported here yet"
    assert {:error, why} = read(context, "storage: {postgres: {url: mysql://x}}\n")
    assert why =~ "storage: holds postgres"
  end

  test "reads notify's targets, each telling the org's agents", context do
    yaml = """
    org: acme
    channels:
      slack: {type: slack, token: xoxb-1, app_token: xapp-1}
    notify:
      ops: {channel: slack, room: "#ops", approvers: ["@maria"]}
      audit: {webhook: {url: https://hooks.example.com/wardrik, secret: "${SECRET}"}}
    """

    assert {:ok, config} = read(context, yaml, %{"SECRET" => "shh"})

    assert Enum.sort(config.notify[:targets]) == [
             {"audit",
              {Wardrik.Notify.Webhook,
               url: "https://hooks.example.com/wardrik", secret: "shh", orgs: ["acme"]}},
             {"ops",
              {Wardrik.Notify.Room,
               channel: "slack", room: "#ops", approvers: ["@maria"], orgs: ["acme"]}}
           ]
  end

  test "refuses a notify target that doesn't read", context do
    for {target, why} <- [
          {~s({channel: teams, room: "#ops"}), "notify.ops.channel: names none of channels"},
          {~s({channel: slack, room: "#ops", to: x}), "notify.ops: a room takes"},
          {~s({channel: slack, room: "#ops", approvers: maria}), "notify.ops.approvers:"},
          {~s({webhook: {url: x, method: put}}), "notify.ops.webhook: takes url and secret"},
          {~s({email: x}), "notify.ops: is a room"}
        ] do
      yaml = "channels: {slack: {type: slack, token: x}}\nnotify: {ops: #{target}}\n"
      assert {:error, message} = read(context, yaml)
      assert message =~ why
    end

    assert {:error, message} = read(context, ~s(notify: {"a:b": {email: x}}\n))
    assert message =~ "isn't a target's name"
    assert {:error, message} = read(context, "notify: [x]\n")
    assert message =~ "notify: is a target for each name"
  end

  test "reads which tools a server gates, whom it trusts, and whether workers are trusted",
       context do
    assert {:ok, config} =
             read(context, """
             mcp:
               github: {url: "https://api.githubcopilot.com/mcp/", gated: [create_*], trusted: true}
             http: {trusted_workers: true}
             """)

    assert [{"github", github}] = config.mcp
    assert github[:gated] == ["create_*"]
    assert github[:trusted] == true
    assert config.trusted_workers
  end

  test "says where a key doesn't read", context do
    refused = [
      {"nope: 1", "nope: isn't a key"},
      {"mcp: {a: {url: x, command: y}}", "mcp.a: has a url or a command, not both"},
      {"mcp: {a: {url: x, cwd: /tmp}}", "mcp.a.cwd: isn't supported here yet"},
      {"mcp: {a: {url: x, gated: some}}",
       "mcp.a.gated: is true, false, or the server's tool names"},
      {"mcp: {a: {url: x, gated: [1]}}",
       "mcp.a.gated: is true, false, or the server's tool names"},
      {"mcp: {a: {url: x, trusted: yes please}}", "mcp.a.trusted: is true or false"},
      {"http: {trusted_workers: always}", "http.trusted_workers: is true or false"},
      {"mcp: {a: {url: x, colour: red}}", "mcp.a.colour: isn't a key of a server"},
      {"mcp: {a: {args: []}}", "mcp.a: has a command"},
      {"mcp: {a: 1}", "mcp.a: is a server's keys"},
      {"mcp: [a]", "mcp: is a server for each name"},
      {"oauth: {providers: {g: {colour: red}}}",
       "oauth.providers.g.colour: isn't a key of a provider"},
      {"oauth: {providers: {g: 1}}", "oauth.providers.g: is a provider's keys"},
      {"oauth: {providers: {}, redirect: {}}", "oauth.redirect: isn't supported here yet"},
      {"oauth: {providers: {}, other: {}}", "oauth.other: isn't a key of oauth"},
      {"oauth: 1", "oauth: holds providers"},
      {"channels: {Slack: {type: slack}}", "channels.Slack: isn't a channel's name"},
      {"channels: {slack: {type: teams}}", "channels.slack.type: is the kind of channel"},
      {"channels: {slack: {token: t}}", "channels.slack.type: is the kind of channel"},
      {"channels: {slack: {type: slack, admins: []}}",
       "channels.slack.admins: isn't supported here yet"},
      {"channels: {slack: {type: slack, colour: red}}", "channels.slack.colour: isn't a key"},
      {"channels: {slack: {type: slack, approvers: maria}}",
       "channels.slack.approvers: is anyone"},
      {"channels: {slack: {type: slack, approvers: [1]}}", "channels.slack.approvers: is anyone"},
      {"channels: [a]", "channels: is a channel for each name"},
      {"vault: {keys: k}", "vault: holds keys"},
      {"http: {port: high}", "http.port: is a port number"},
      {"http: {ip: here}", "http.ip: is an address"},
      {"http: 1", "http: holds port, ip and trusted_workers"},
      {"defaults: 1", "defaults: is what an agent's file takes"},
      {"brave: {key: x}", "brave: holds api_key"},
      {"models: 1", "models: holds each model's price"},
      {"models: {a:b: 1}", "models.a:b: holds input and output"},
      {"models: {a:b: {per: day}}", "models.a:b.per: isn't a setting"},
      {"models: {a:b: {input: 1}}", "models.a:b: a:b's price gives its input and output."},
      {"models: {a:b: {priced_as: nope:nope}}", "models.a:b: nope:nope has no price"},
      {"models: {a:b: {input: 1, output: 1, markup: lots}}",
       "models.a:b: a:b's markup is a number."},
      {"org: ${MISSING}", "names ${MISSING}, which neither"},
      {"- a", "is a set of keys"},
      {"a: [", "isn't YAML"}
    ]

    for {yaml, why} <- refused do
      assert {:error, message} = read(context, yaml)
      assert message =~ why, "#{yaml} said #{message}"
    end
  end

  test "reads ${NAME} from the vault where the environment doesn't set it", context do
    write(context, "config.yaml", "org: ${ORG}\ndefaults: {model: \"${MODEL}\"}\n")
    vault = fn name -> if name == "ORG", do: {:ok, "acme"}, else: :error end
    dirs = Dirs.new(context.env)

    assert {:ok, %Config{org: "acme"}} =
             Config.read(dirs, Map.put(context.env, "MODEL", "m"), vault)

    assert {:error, why} = Config.read(dirs, context.env, vault)

    assert why =~
             "names ${MODEL}, which neither the environment, the env file nor the vault holds"

    write(context, "config.yaml", "http: {port: \"${PORT}\"}\n")
    assert {:error, why} = Config.read(dirs, context.env, fn _name -> {:ok, "1"} end)
    assert why =~ "names ${PORT}, which neither the environment nor the env file sets"
    assert {:error, _why} = Config.bootstrap(dirs, context.env)
  end

  test "reads the trees agents beyond their owners may mount", context do
    yaml = """
    workspace:
      shared:
        acme/runbooks: {read: ["acme/*"], write: [acme/agent/ops]}
    """

    assert {:ok,
            %Config{
              workspace: [
                shared: %{"acme/runbooks" => [read: ["acme/*"], write: ["acme/agent/ops"]]}
              ]
            }} =
             read(context, yaml)

    assert {:error, why} = read(context, "workspace: {shared: {acme: {read: acme}}}")
    assert why =~ "workspace.shared.acme: holds read and write"
    assert {:error, why} = read(context, "workspace: {trees: {}}")
    assert why =~ "workspace: holds shared"
  end

  test "reads an empty file as the defaults", context do
    assert {:ok, %Config{org: "default"}} = read(context, "")
  end
end

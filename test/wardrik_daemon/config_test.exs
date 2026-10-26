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
    brave: {api_key: "${UNSET}"}
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
    assert config.warnings == ["brave isn't supported here yet, so it's passed over"]
  end

  test "says where a key doesn't read", context do
    refused = [
      {"nope: 1", "nope: isn't a key"},
      {"mcp: {a: {url: x, command: y}}", "mcp.a: has a url or a command, not both"},
      {"mcp: {a: {url: x, gated: true}}", "mcp.a.gated: isn't supported here yet"},
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
      {"http: 1", "http: holds port and ip"},
      {"defaults: 1", "defaults: is what an agent's file takes"},
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

  test "reads an empty file as the defaults", context do
    assert {:ok, %Config{org: "default"}} = read(context, "")
  end
end

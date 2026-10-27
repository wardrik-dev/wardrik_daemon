# WardrikDaemon

Wardrik as a daemon: agents from files, `config.yaml`, an HTTP API, and the `wardrik` command.

## Try it

From this repository:

```sh
mix release
export PATH="$PWD/_build/dev/rel/wardrikd/bin:$PATH"

wardrik init --org acme
echo 'ANTHROPIC_API_KEY=sk-ant-...' >> ~/.config/wardrik/env
wardrik start
wardrik ask assistant "What can you do?"
```

`init` writes `~/.config/wardrik/config.yaml`, the front door in `agents/assistant.md`, and an
`env` file only you can read. Tell the front door an outcome, as "tell me when
https://elixir-lang.org/atom.xml has a new post", and it proposes the work as the calls that do it:
a worker it defines, with the triggers that start it. Approve them with `wardrik approve`, and the
work runs on its own. Its body is its instructions, then a playbook to edit as you like. `start` runs the daemon in the background, and every other command reaches
it over its HTTP API, at `127.0.0.1:4747` unless `config.yaml` says otherwise.

From source, without a release, `mix wardrik serve` runs the daemon in the foreground, and
`mix wardrik ls` and the rest are the same commands.

## Agents

An agent is a Markdown file in `agents/`. Its frontmatter says what it is and may do, and its body
is its instructions:

```markdown
---
description: Watches the incident queue and says what needs an engineer.
model: anthropic:claude-sonnet-5
tools: [linear/*]
policy: careful
triggers:
  - {name: daily, every: "0 9 * * *", timezone: America/Los_Angeles, prompt: What's new?}
channels: [slack]
---
You watch the incident queue. Summarise anything new, and say which issues need an engineer.
```

Its ID is the deployment's org and the file's name, as `acme/triage`, or `acme/@jon/triage` with
`user: jon`. Every other key is a definition's, and what a file leaves out comes from
`config.yaml`'s `defaults`. `wardrik reload` reads the files again: a changed file's agent takes
what it says from its next turn, and a removed file's agent is forgotten. The API can't forget an
agent a file declares. A file that doesn't read is logged, and `wardrik doctor` says why.

The daemon ships `run_lua`, Lua in a sealed sandbox, for arithmetic, reshaping data and the time
now, `web_search`, through Brave, with `brave.api_key`, and `deep_research`, which splits a topic
across angles and has a subagent with the agent's own tools research each at once. See
[WardrikLua](https://hexdocs.pm/wardrik_lua), [WardrikBrave](https://hexdocs.pm/wardrik_brave) and
[WardrikResearch](https://hexdocs.pm/wardrik_research).

With `files` in its `tools`, an agent keeps a tree of files of its own in the store, and
`context: [MEMORY.md]` reads files into every turn: that's its memory. See
[WardrikWorkspace](https://hexdocs.pm/wardrik_workspace).

Policies are YAML files in `policies/`, by name: `policies/careful.yaml` is `policy: careful`.

## config.yaml

```yaml
org: acme
base_url: https://agents.acme.example   # where people and services reach it

defaults:
  model: anthropic:claude-haiku-4-5

mcp:
  github:
    url: https://api.githubcopilot.com/mcp/
    credential: github
    only: [list_commits, get_commit]

oauth:
  providers:
    github:
      issuer: https://github.com/login/oauth
      resource: https://api.githubcopilot.com/mcp/
      client_id: ${GITHUB_CLIENT_ID}
      client_secret: ${GITHUB_CLIENT_SECRET}
      scopes: [repo]
      flow: device

channels:
  slack:
    type: slack
    token: ${SLACK_BOT_TOKEN}
    app_token: ${SLACK_APP_TOKEN}       # Socket Mode; or signing_secret, over HTTP
    approvers: ["@maria"]

brave:
  api_key: ${BRAVE_API_KEY}             # web_search; or seal it: wardrik vault put BRAVE_API_KEY

notify:
  ops: {channel: slack, room: "#ops", approvers: ["@maria"]}
  audit: {webhook: {url: https://hooks.example.com/wardrik, secret: "${WEBHOOK_SECRET}"}}

http:
  port: 4747
  ip: 127.0.0.1

storage:
  postgres:
    url: ${DATABASE_URL}                # postgres://user:pass@host/db; ?ssl=true for TLS
```

`defaults` are what every agent is given where its definition says nothing, however it was
defined: from a file, over the HTTP API, or by the front door.

`models` says what a model costs where the catalog has no price for it in dollars, or not the one
to count, so budgets and spending hold it: its own `input` and `output`, and `cache_read` and
`cache_write`, in dollars per million tokens, or `priced_as` another model, each with a `markup`
if you like, `0.1` for 10% more:

```yaml
models:
  zai_coding_plan:glm-5.1: {priced_as: zai:glm-5.1}
  openrouter:qwen3-coder: {input: 0.3, output: 1.2}
```

`${NAME}` is the environment's, the `env` file's, or the deployment's secret of that name, which
`wardrik vault put NAME` seals. `vault`, `http` and `storage` read the environment alone, since
they're read before the vault opens. A key nothing takes is refused, and the daemon says where.

`workspace.shared` names the trees of files agents beyond their owners may mount, each with the
agents, by resource pattern, that may `read` it and those that may `write` it:

```yaml
workspace:
  shared:
    acme/runbooks:
      read: ["acme/*"]
      write: [acme/agent/ops, "acme/agent/ops/*"]
```

`notify` names the targets agents' notices go to: a room of a channel, or a webhook. An agent file
routes to them, or to a room itself, as `notify: {to: ["slack:#updates"], on: [finished, failed]}`.

`storage` keeps everything in Postgres, which the daemon creates its table in as it starts, one
node at a time. Point it at the primary. Without it, everything is kept on the node's disk.

`orgs` declares the orgs beside the deployment's own `org`, each with the servers, channels and
notify targets its agents use, by the names their sections give them, and the policy in
`policies/` it's held to:

```yaml
org: platform

orgs:
  "*":                       # every org
    mcp: [search]
    policy: base
  payments:
    mcp: [stripe, github]
    channels: [payments-slack]
    notify: [audit]
    policy: payments-strict
  growth:
    mcp: [github]
```

Every agent of an org is held to `"*"`'s policy, then its own, then its definition's, and the
strictest decides; a definition narrows them, never widens them. A policy's budget is the org's:
its agents spend from it together, and each org spends `"*"`'s apart, except a budget per turn,
which stays each agent's. An org whose policy `policies/` doesn't hold runs none of its agents.
A server, channel or target no entry lists is the deployment's own org's, and a channel serves one
org, or every org where `"*"` lists it. Any other org is refused: no agent, secret, server or token
over its agents is kept for it. Each org's agents reach a server with their own credential, so
payments and growth each seal a `github` of their own: `wardrik vault put github --org payments`.

`tools`, `tokens`, `cluster` and `ssh` aren't run yet, and are passed over with a warning.

The vault's key is `vault.keys`, `WARDRIK_VAULT_KEY`, or `vault_key` in the data home, made the
first time the daemon starts.

## The wardrik command

| Command | Does |
| --- | --- |
| `serve`, `start`, `stop`, `logs` | runs the daemon in the foreground or background, stops it, shows its log |
| `service install` | runs it as a systemd user service |
| `init`, `reload`, `status` | writes a first config, reads the agent files again, says where it runs |
| `doctor` | checks the env file, `config.yaml`, the vault's key, each MCP server and channel, OAuth's callback, and every agent file and policy, running or not |
| `ask AGENT MESSAGE` | asks, and prints the answer as it comes |
| `ls`, `show AGENT`, `triggers AGENT` | lists agents, says what one is and does |
| `history AGENT`, `agent rm AGENT` | prints an agent's conversation, removes one |
| `parked`, `approve AGENT CALL`, `deny AGENT CALL` | the calls agents wait on a person for |
| `token create/list/revoke` | API tokens |
| `vault put/ls/rm NAME` | secrets, the deployment's or an org's or a person's with `--org` and `--user` |
| `audit` | what people changed |

The command acts with a token the daemon writes to `cli_token` in the data home each time it starts.
`WARDRIK_URL` and `WARDRIK_TOKEN` point it at another daemon.

## Directories

| Variable | Default | Holds |
| --- | --- | --- |
| `WARDRIK_CONFIG_DIR` | `~/.config/wardrik` | `config.yaml`, `agents/`, `policies/` and `env` |
| `WARDRIK_DATA_DIR` | `~/.local/share/wardrik/store` | the store |
| `WARDRIK_DATA_HOME` | `~/.local/share/wardrik` | `vault_key`, `cli_token` and the node's `cookie` |
| `WARDRIK_STATE_DIR` | `~/.local/state/wardrik` | logs |

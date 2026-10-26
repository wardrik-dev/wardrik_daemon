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

`init` writes `~/.config/wardrik/config.yaml`, an agent in `agents/assistant.md`, and an `env`
file only you can read. `start` runs the daemon in the background, and every other command reaches
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

http:
  port: 4747
  ip: 127.0.0.1
```

`${NAME}` is the environment's, the `env` file's, or the deployment's secret of that name, which
`wardrik vault put NAME` seals. `vault` and `http` read the environment alone, since they're read
before the vault opens. A key nothing takes is refused, and the daemon says where.

`workspace.shared` names the trees of files agents beyond their owners may mount, each with the
agents, by resource pattern, that may `read` it and those that may `write` it:

```yaml
workspace:
  shared:
    acme/runbooks:
      read: ["acme/*"]
      write: [acme/agent/ops, "acme/agent/ops/*"]
```

`orgs`, `tools`, `notify`, `brave`, `tokens`, `storage`, `cluster` and `ssh` aren't run yet, and
are passed over with a warning.

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

# Changelog

## 0.1.0-rc.1 (2026-10-30)

- The daemon: Wardrik on the node's disk or in Postgres, the HTTP API, and the channels
  `config.yaml` names.
- `config.yaml`: org, base URL, defaults, models, MCP servers, OAuth providers, channels, notify
  targets, orgs, storage, the vault's keys and where HTTP listens. `${NAME}` reads the environment,
  the env file or the vault.
- Agents from Markdown files in `agents/`, and policies from `policies/`, read again on reload.
  `defaults` apply to every agent.
- `wardrik init`, which sets up the front door: `assistant.md`, an agent that works with the org's
  agents, with a playbook to edit.
- The `wardrik` command over the HTTP API: ask with the answer streamed, agents, approvals,
  triggers, servers, connections, tokens, the vault and the audit.
- `serve`, `start`, `stop`, `logs` and `service install` in the release's script, and
  `wardrik doctor`, which checks what the daemon reads.
- Tools agents may name: `files` over a workspace of their own, `run_lua` in a sealed sandbox,
  `web_search` through Brave, and `deep_research`.
- An installer for Linux, x86_64 or aarch64, checked against `SHA256SUMS`, and an image for
  elsewhere.

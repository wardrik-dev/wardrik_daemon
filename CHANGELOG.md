# Changelog

## 0.1.0 (unreleased)

- The daemon: a Wardrik on the node's disk, the HTTP API, and the channels `config.yaml` names.
- `config.yaml`: org, base URL, defaults, MCP servers, OAuth providers, channels, the vault's keys
  and where HTTP listens, with `${NAME}` from the environment, the env file, or the vault.
- Agents from Markdown files in `agents/`, and policies from `policies/`, read again on reload,
  and kept from the API.
- The `wardrik` command over the HTTP API: ask with the answer streamed, list, show, decide, reload,
  tokens, secrets and the audit; `serve`, `start`, `stop`, `logs` and `service install` in the
  release's script.
- `wardrik doctor`: checks what the daemon reads, running or not, a line each.
- Agents' files: `files` in `tools`, `context` and `workspace` in agent files, and `config.yaml`'s
  `workspace.shared`.
- `run_lua`, Lua in a sealed sandbox, among the tools agents may name.

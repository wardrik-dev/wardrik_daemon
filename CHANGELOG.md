# Changelog

## Unreleased

- `config.yaml` is checked against the libraries' own `NimbleOptions` schemas, so it takes every
  option they do, and an error names where it is, as
  `oauth.providers.google: unknown options [:colour], valid options are: ...`.
- New keys:
  - `deployment_keys`, `true` unless set, so agents still use the API keys sealed in the
    deployment's vault. Also `deployment`, `idle_timeout`, `retention` and `triggers`.
  - `oauth`: `client_name` and `req_options`, and a provider's `authorization_params`.
  - `channels`: `offering`, `deciding` and `req_options`.
  - `notify`: `retries` and `req_options`, and a webhook's `req_options`.
  - `mcp`: `cost`.
- `oauth` starts sign-ins whenever it's set, even with no `providers`, so orgs and people can add
  their own.
- Now refused:
  - `notify`'s targets at its top level. They go in `notify.targets`.
  - Options Wardrik refused only as it started, as `flow: carrier_pigeon` or an MCP `url` with no
    scheme. `config.yaml` and `wardrik doctor` refuse them now.
  - `org` or `base_url` that isn't a string, and `vault.keys` that aren't strings.
- Errors use NimbleOptions' words, as `storage: unknown options [:s3]`. `channels.*.admins` and
  `create`, `mcp.*.cwd`, and `oauth.client` and `redirect` are unknown options, not "not supported
  yet".

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

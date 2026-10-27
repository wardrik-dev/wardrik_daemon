import Config

config :req_llm, receive_timeout: 120_000, thinking_timeout: 300_000

if config_env() == :test, do: config(:logger, level: :warning)

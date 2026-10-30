defmodule WardrikDaemon.CLIToken do
  @moduledoc """
  Issues the token the `wardrik` command acts with.

  Each time the daemon starts, it revokes the last token and makes a new one: an owner token on
  every resource, good for a year. It's written to `cli_token` in the data home, readable only by
  you, as JSON with the token's `id`, its `secret`, and the `url` the HTTP API listens at.
  """

  alias WardrikCore.Principal

  @lifetime 365 * 24 * 60 * 60

  @doc "Revokes the token at `path`, makes a new one on `wardrik`, and writes it to `path` with `url`."
  @spec issue(atom(), Path.t(), String.t()) :: :ok
  def issue(wardrik, path, url) do
    scope = Wardrik.as(wardrik, %Principal{id: "deployment"}, roles: [:owner], resources: ["*"])
    revoked(scope, path)

    {:ok, issued} =
      Wardrik.Tokens.create(scope,
        name: "wardrik command",
        roles: ["owner"],
        resources: ["*"],
        expires_in: @lifetime
      )

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(%{id: issued.token.id, secret: issued.secret, url: url}))
    File.chmod!(path, 0o600)
  end

  @doc "Returns the `url` and `secret` of the token at `path`, or `:error` if there's none."
  @spec read(Path.t()) :: {:ok, %{url: String.t(), secret: String.t()}} | :error
  def read(path) do
    with {:ok, text} <- File.read(path),
         {:ok, %{"url" => url, "secret" => secret}} <- JSON.decode(text) do
      {:ok, %{url: url, secret: secret}}
    else
      _missing -> :error
    end
  end

  defp revoked(scope, path) do
    with {:ok, text} <- File.read(path),
         {:ok, %{"id" => id}} <- JSON.decode(text),
         do: Wardrik.Tokens.revoke(scope, id)
  end
end

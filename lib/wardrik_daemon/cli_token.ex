defmodule WardrikDaemon.CLIToken do
  @moduledoc """
  The CLI token is what the `wardrik` command acts with: an owner token on everything, made each
  time the daemon starts, in place of the last, and written to `cli_token` in the data home, which
  only you can read. It holds where the HTTP API listens too.
  """

  alias WardrikCore.Principal

  @lifetime 365 * 24 * 60 * 60

  @doc "Makes a new token on `wardrik`, revoking the one at `path`, and writes it there with `url`."
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

  @doc "Returns where the HTTP API listens and the secret to present there, from the token at `path`."
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

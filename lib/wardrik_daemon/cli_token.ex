defmodule WardrikDaemon.CLIToken do
  @moduledoc """
  Issues the token the `wardrik` command acts with.

  Each time the daemon starts, it revokes the last token and makes a new one, good for a year:
  a `WardrikDaemon.Tokens` token for the deployment's admin, `user:admin`, whom
  `WardrikDaemon.Config.Access` binds to `operator` in every org. It's written to `cli_token` in
  the data home, readable only by you, as JSON with the token's `id`, its `secret`, and the `url`
  the HTTP API listens at.
  """

  alias WardrikDaemon.Config.Access
  alias WardrikDaemon.Tokens

  @doc "Revokes the token at `path`, makes a new one in `store`, and writes it to `path` with `url`."
  @spec issue(WardrikStore.t(), Path.t(), String.t()) :: :ok
  def issue(store, path, url) do
    revoked(store, path)

    {:ok, %{token: token, secret: secret}} =
      Tokens.create(store,
        name: "wardrik command",
        subject: "user:" <> Access.admin(),
        expires: DateTime.add(DateTime.utc_now(), 365, :day)
      )

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(%{id: token.id, secret: secret, url: url}))
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

  defp revoked(store, path) do
    with {:ok, text} <- File.read(path),
         {:ok, %{"id" => id}} <- JSON.decode(text),
         do: Tokens.revoke(store, id)
  end
end

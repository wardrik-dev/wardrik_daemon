defmodule WardrikDaemon.Config.Channels do
  @moduledoc """
  Reads `config.yaml`'s `channels`: the chat apps agents are reached through.

      channels:
        slack:
          type: slack
          token: ${SLACK_BOT_TOKEN}
          app_token: ${SLACK_APP_TOKEN}
          approvers: ["@maria"]

  Each channel has a name of your own: lower-case letters, digits and `-`, starting with a letter.
  `shell`, `ssh`, `terminal` and `oauth` are taken.

  ## Keys

    * `type` - required. `slack` is the only type so far.
    * `token` - the bot's token. Without one, the channel keeps a token in the vault for each
      workspace it's added to.
    * `approvers` - who may decide on calls agents wait on a person for: `@handle`s, or `anyone`.
      `[]` unless set.
    * `signing_secret`, `app_token`, `client_id`, `client_secret` and `redirect_uri` - Slack's.
      See `WardrikSlack`.

  A channel serves the deployment's own org's agents. `orgs` may give it to another org, or to
  every org. See `WardrikDaemon.Config.Orgs`.
  """

  @types %{
    "slack" =>
      {WardrikSlack,
       %{
         "signing_secret" => :signing_secret,
         "app_token" => :app_token,
         "client_id" => :client_id,
         "client_secret" => :client_secret,
         "redirect_uri" => :redirect_uri
       }}
  }
  @common ~w(type token approvers)
  @later ~w(admins create)

  @doc "Returns the channels `section` names, as Wardrik's `:channels` option takes them, serving `org`'s agents."
  @spec read(map() | nil, String.t()) :: {:ok, keyword()} | {:error, String.t()}
  def read(nil, _org), do: {:ok, []}

  def read(section, org) when is_map(section) do
    read = Enum.map(section, fn {name, channel} -> {name, channel(name, channel, org)} end)

    case Enum.find(read, &match?({_name, {:error, _why}}, &1)) do
      nil -> {:ok, for({name, {:ok, channel}} <- read, do: {name, channel})}
      {name, {:error, why}} -> {:error, "channels.#{name}#{why}"}
    end
  end

  def read(_section, _org), do: {:error, "channels: is a channel for each name"}

  defp channel(name, %{"type" => type} = channel, org) do
    with :ok <- named(name),
         {:ok, {adapter, keys}} <- typed(type),
         :ok <- known(channel, keys),
         {:ok, approvers} <- approvers(Map.get(channel, "approvers", [])) do
      own = for {key, option} <- keys, Map.has_key?(channel, key), do: {option, channel[key]}

      {:ok, {adapter, added(channel) ++ [owner: org, approvers: approvers] ++ own}}
    end
  end

  defp channel(_name, _channel, _org), do: {:error, ".type: is the kind of channel: slack"}

  defp added(%{"token" => token}) when is_binary(token), do: [token: token]
  defp added(_channel), do: [installations: :stored]

  defp named(name) do
    if Regex.match?(~r/\A[a-z][a-z0-9-]*\z/, name) and name not in ~w(shell ssh terminal oauth),
      do: :ok,
      else:
        {:error,
         ": isn't a channel's name: lower-case letters, digits and -, starting with a letter"}
  end

  defp typed(type) do
    case Map.fetch(@types, type) do
      {:ok, adapter} -> {:ok, adapter}
      :error -> {:error, ".type: is the kind of channel: slack"}
    end
  end

  defp known(channel, keys) do
    case Enum.find(Map.keys(channel), &(&1 not in @common and not Map.has_key?(keys, &1))) do
      nil -> :ok
      key when key in @later -> {:error, ".#{key}: isn't supported here yet"}
      key -> {:error, ".#{key}: isn't a key of this kind of channel"}
    end
  end

  defp approvers("anyone"), do: {:ok, :anyone}

  defp approvers(names) when is_list(names) do
    if Enum.all?(names, &is_binary/1),
      do: {:ok, names},
      else: {:error, ".approvers: is anyone, or a list of who may decide"}
  end

  defp approvers(_names), do: {:error, ".approvers: is anyone, or a list of who may decide"}
end

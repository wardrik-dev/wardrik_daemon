defmodule WardrikDaemon.Config.Notify do
  @moduledoc """
  Reads `config.yaml`'s `notify`: the targets agents' notices go to, each by a name of your own.

      notify:
        ops: {channel: slack, room: "#ops", approvers: ["@maria"]}
        audit: {webhook: {url: https://hooks.example.com/wardrik, secret: "${WEBHOOK_SECRET}"}}

  A target is one of:

    * a room - `channel`, one of `channels`, its `room`, and optional `approvers`.
    * a webhook - `webhook`, with `url` and an optional `secret`.

  A target's name can't hold `:`, which names a channel's room. A target tells the deployment's own
  org's agents unless `orgs` says otherwise. See `Wardrik.Notify`.
  """

  @doc "Returns the targets `section` names, as Wardrik's `:notify` option takes them, telling `org`'s agents. `channels` are the channels' names."
  @spec read(map() | nil, String.t(), [String.t()]) :: {:ok, keyword()} | {:error, String.t()}
  def read(nil, _org, _channels), do: {:ok, []}

  def read(section, org, channels) when is_map(section) do
    read = Enum.map(section, fn {name, target} -> {name, target(name, target, channels)} end)

    case Enum.find(read, &match?({_name, {:error, _why}}, &1)) do
      nil ->
        {:ok,
         targets:
           for({name, {:ok, {module, opts}}} <- read, do: {name, {module, opts ++ [orgs: [org]]}})}

      {name, {:error, why}} ->
        {:error, "notify.#{name}#{why}"}
    end
  end

  def read(_section, _org, _channels), do: {:error, "notify: is a target for each name"}

  defp target(name, target, channels) do
    if String.contains?(name, ":"),
      do: {:error, ": isn't a target's name, since : names a channel's room"},
      else: typed(target, channels)
  end

  defp typed(%{"channel" => channel, "room" => room} = target, channels)
       when is_binary(channel) and is_binary(room) do
    approvers = Map.get(target, "approvers", [])

    cond do
      Map.keys(target) -- ~w(channel room approvers) != [] ->
        {:error, ": a room takes channel, room and approvers"}

      channel not in channels ->
        {:error, ".channel: names none of channels"}

      not (is_list(approvers) and Enum.all?(approvers, &is_binary/1)) ->
        {:error, ".approvers: is a list of people, as the channel names them"}

      true ->
        {:ok, {Wardrik.Notify.Room, channel: channel, room: room, approvers: approvers}}
    end
  end

  defp typed(%{"webhook" => %{"url" => url} = webhook} = target, _channels)
       when map_size(target) == 1 and is_binary(url) do
    if Map.keys(webhook) -- ~w(url secret) == [],
      do:
        {:ok,
         {Wardrik.Notify.Webhook,
          Enum.reject([url: url, secret: webhook["secret"]], &is_nil(elem(&1, 1)))}},
      else: {:error, ".webhook: takes url and secret"}
  end

  defp typed(_target, _channels),
    do: {:error, ": is a room, with channel and room, or a webhook, with url"}
end

defmodule WardrikDaemon.Config.Orgs do
  @moduledoc """
  Reads `config.yaml`'s `orgs`: the orgs beside the deployment's own.

      orgs:
        "*":
          mcp: [search]
          policy: base
        payments:
          mcp: [stripe, github]
          channels: [payments-slack]
          notify: [audit]
          policy: payments-strict

  ## Keys

    * `mcp`, `channels`, `notify` - the servers, channels and targets the org's agents use, by the
      names their sections give them.
    * `policy` - the policy in `policies/` the org's agents are held to.

  `"*"` is every org: what it lists, every org uses, and its policy holds every org.

  A server, channel or target no entry lists is the deployment's own org's. A channel serves one
  org, or every org if `"*"` lists it.
  """

  @keys ~w(mcp channels notify policy)
  @name ~r/\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/

  @type entry() :: %{
          mcp: [String.t()],
          channels: [String.t()],
          notify: [String.t()],
          policy: String.t() | nil
        }

  @doc """
  Returns each org's entry, `"*"`'s too.

  `defined` holds the names `mcp`, `channels` and `notify` define, which entries may list.
  """
  @spec read(map() | nil, %{String.t() => [String.t()]}) ::
          {:ok, %{String.t() => entry()}} | {:error, String.t()}
  def read(nil, _defined), do: {:ok, %{}}

  def read(section, defined) when is_map(section) do
    read = Enum.map(section, fn {org, entry} -> {org, entry(org, entry, defined)} end)

    case Enum.find(read, &match?({_org, {:error, _why}}, &1)) do
      nil -> {:ok, Map.new(read, fn {org, {:ok, entry}} -> {org, entry} end)}
      {org, {:error, why}} -> {:error, "orgs.#{org}#{why}"}
    end
  end

  def read(_section, _defined), do: {:error, "orgs: is an entry for each org"}

  @doc """
  Returns the orgs whose agents use the `kind` of thing called `name`.

  Returns `:all` if `"*"` lists it, the orgs whose entries list it, or `[org]` if none does.
  """
  @spec using(%{String.t() => entry()}, atom(), String.t(), String.t()) :: :all | [String.t()]
  def using(orgs, kind, name, org) do
    listing = for {listed, entry} <- orgs, name in Map.fetch!(entry, kind), do: listed

    cond do
      "*" in listing -> :all
      listing == [] -> [org]
      true -> Enum.sort(listing)
    end
  end

  defp entry(org, nil, defined), do: entry(org, %{}, defined)

  defp entry(org, entry, defined) when is_map(entry) do
    with :ok <- named(org),
         :ok <- known(entry),
         {:ok, mcp} <- listed(entry, "mcp", defined),
         {:ok, channels} <- listed(entry, "channels", defined),
         {:ok, notify} <- listed(entry, "notify", defined),
         {:ok, policy} <- policy(entry["policy"]) do
      {:ok, %{mcp: mcp, channels: channels, notify: notify, policy: policy}}
    end
  end

  defp entry(_org, _entry, _defined),
    do: {:error, ": takes mcp, channels and notify, each a list of names, and policy"}

  defp named("*"), do: :ok
  defp named("deployment"), do: {:error, ": is the deployment's own namespace, not an org"}

  defp named(org) do
    if Regex.match?(@name, org),
      do: :ok,
      else: {:error, ": isn't an org's name: letters, digits, _, . and -"}
  end

  defp known(entry) do
    case Enum.find(Map.keys(entry), &(&1 not in @keys)) do
      nil -> :ok
      key -> {:error, ".#{key}: isn't a key of an org: mcp, channels, notify or policy"}
    end
  end

  defp listed(entry, key, defined),
    do: entry |> Map.get(key, []) |> names(key, Map.get(defined, key, []))

  defp names(names, key, known) when is_list(names) do
    case Enum.find(names, &(not is_binary(&1) or &1 not in known)) do
      nil ->
        {:ok, names}

      unknown when is_binary(unknown) ->
        {:error, ".#{key}: names #{unknown}, which #{key} doesn't define"}

      _other ->
        names(nil, key, known)
    end
  end

  defp names(_names, key, _known), do: {:error, ".#{key}: is a list of names #{key} defines"}

  defp policy(nil), do: {:ok, nil}
  defp policy(name) when is_binary(name), do: {:ok, name}
  defp policy(_policy), do: {:error, ".policy: names a policy in policies/"}
end

defmodule WardrikDaemon.Config.OAuth do
  @moduledoc """
  Reads `config.yaml`'s `oauth`: the providers people connect accounts with, each named like the
  credential it grants. See `WardrikOAuth.Provider` for what each key becomes.
  """

  @keys %{
    "issuer" => :issuer,
    "resource" => :resource,
    "client_id" => :client_id,
    "client_secret" => :client_secret,
    "authorization_endpoint" => :authorization_endpoint,
    "token_endpoint" => :token_endpoint,
    "scopes" => :scopes,
    "flow" => :flow,
    "client_auth" => :client_auth
  }

  @doc "Returns the providers `section` names, as `WardrikOAuth` takes them, or the key that doesn't read."
  @spec read(map() | nil) :: {:ok, keyword()} | {:error, String.t()}
  def read(nil), do: {:ok, []}

  def read(%{"providers" => providers} = section) when is_map(providers) do
    with :ok <- only_providers(section) do
      read = Enum.map(providers, fn {name, provider} -> {name, provider(provider)} end)

      case Enum.find(read, &match?({_name, {:error, _why}}, &1)) do
        nil -> {:ok, for({name, {:ok, opts}} <- read, do: {name, opts})}
        {name, {:error, why}} -> {:error, "oauth.providers.#{name}#{why}"}
      end
    end
  end

  def read(_section), do: {:error, "oauth: holds providers, a provider for each name"}

  defp only_providers(section) do
    case Map.keys(section) -- ["providers"] do
      [] ->
        :ok

      [key | _rest] when key in ["client", "redirect"] ->
        {:error, "oauth.#{key}: isn't supported here yet"}

      [key | _rest] ->
        {:error, "oauth.#{key}: isn't a key of oauth"}
    end
  end

  defp provider(provider) when is_map(provider) do
    case Enum.find(Map.keys(provider), &(not Map.has_key?(@keys, &1))) do
      nil -> {:ok, Enum.map(provider, &option/1)}
      key -> {:error, ".#{key}: isn't a key of a provider"}
    end
  end

  defp provider(_provider), do: {:error, ": is a provider's keys"}

  defp option({"flow", flow}) when flow in ["device", "browser"],
    do: {:flow, String.to_existing_atom(flow)}

  defp option({"client_auth", auth}) when auth in ["post", "basic"],
    do: {:client_auth, String.to_existing_atom(auth)}

  defp option({key, value}), do: {String.to_existing_atom(key), value}
end

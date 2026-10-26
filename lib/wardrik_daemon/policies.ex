defmodule WardrikDaemon.Policies do
  @moduledoc """
  Reads the policies in `policies/`, each a YAML file named for the policy: `policies/careful.yaml`
  is `careful`, which an agent's file names as `policy: careful`. See `WardrikPolicy` for what the
  rules say.

      allow: [web_search, linear/*]
      ask:
        github/create_*: This opens an issue on GitHub.
      deny: [shell/*]
      budget: {usd: 5.00, per: day}
  """

  @doc "Returns each policy in `dir` by name, or why one doesn't read. A missing directory holds none."
  @spec read(Path.t()) :: {:ok, %{String.t() => WardrikPolicy.t()}} | {:error, String.t()}
  def read(dir) do
    read =
      for path <- Path.wildcard(Path.join(dir, "*.{yaml,yml}")),
          do: {path |> Path.basename() |> Path.rootname(), policy(path)}

    case Enum.find(read, &match?({_name, {:error, _why}}, &1)) do
      nil -> {:ok, Map.new(read, fn {name, {:ok, policy}} -> {name, policy} end)}
      {_name, {:error, why}} -> {:error, why}
    end
  end

  defp policy(path) do
    name = path |> Path.basename() |> Path.rootname()

    with {:ok, fields} <- fields(path),
         {:ok, policy} <- WardrikPolicy.decode(fields, name: name) do
      {:ok, policy}
    else
      {:error, why} -> {:error, "#{path}: #{why}"}
    end
  end

  defp fields(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, fields} when is_map(fields) and map_size(fields) > 0 -> {:ok, fields}
      {:ok, _empty} -> {:error, "is empty; a policy that allows every call says default: allow"}
      {:error, error} -> {:error, "isn't YAML: #{Exception.message(error)}"}
    end
  end
end

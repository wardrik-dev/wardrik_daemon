defmodule WardrikDaemon.EnvFile do
  @moduledoc """
  The env file holds variables the daemon sets where its environment doesn't, one `NAME=value` a
  line, after an optional `export`. Blank lines and `#` comments are passed over. It's where the
  keys and tokens `config.yaml` names go, so the file itself holds no secret.
  """

  @doc "Returns `env` with each variable the file at `path` sets that `env` doesn't. A missing file sets none."
  @spec load(Path.t(), %{String.t() => String.t()}) :: %{String.t() => String.t()}
  def load(path, env) do
    case File.read(path) do
      {:ok, text} -> Map.merge(variables(text), env)
      {:error, _reason} -> env
    end
  end

  defp variables(text) do
    text
    |> String.split(["\r\n", "\n"])
    |> Enum.flat_map(&variable/1)
    |> Map.new()
  end

  defp variable(line) do
    line = line |> String.trim() |> String.replace_prefix("export ", "")

    case String.split(line, "=", parts: 2) do
      ["#" <> _comment | _rest] ->
        []

      [name, value] ->
        if Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*\z/, name),
          do: [{name, unquoted(value)}],
          else: []

      _blank ->
        []
    end
  end

  defp unquoted("\"" <> rest), do: String.trim_trailing(rest, "\"")
  defp unquoted("'" <> rest), do: String.trim_trailing(rest, "'")
  defp unquoted(value), do: value
end

defmodule WardrikDaemon.AgentFile do
  @moduledoc """
  Reads an agent file: a Markdown file in `agents/`.

  The frontmatter is the agent's definition, and the body is its instructions. This is
  `agents/triage.md`:

      ---
      description: Watches the incident queue and says what needs an engineer.
      model: anthropic:claude-sonnet-5
      tools: [linear/*]
      policy: careful
      ---
      You watch the incident queue. Summarise anything new, and say which issues need an engineer.

  Three keys make the agent's ID:

    * `name` - the file's name unless set.
    * `org` - the deployment's `org`. A file that names another org doesn't read.
    * `user` - the person the agent works for, if any.

  The file above is `acme/triage`. With `user: jon`, it's `acme/@jon/triage`.

  Every other key is part of the definition. See `Wardrik.Definition`. Keys the file leaves out
  come from `config.yaml`'s `defaults`. A file with no frontmatter is all instructions.
  """

  alias WardrikDaemon.Config

  @doc "Reads the file at `path`. Returns the agent's ID and its definition, with `defaults` filled in."
  @spec read(Path.t(), Config.t()) :: {:ok, String.t(), map()} | {:error, String.t()}
  def read(path, %Config{} = config) do
    with {:ok, text} <- File.read(path),
         {:ok, fields, body} <- split(text),
         {:ok, id} <- id(path, fields, config.org) do
      {:ok, id, definition(fields, body, config.defaults)}
    else
      {:error, reason} when is_atom(reason) -> {:error, "#{path}: #{:file.format_error(reason)}"}
      {:error, why} -> {:error, "#{path}: #{why}"}
    end
  end

  defp split("---" <> rest) do
    with [front, body] <- String.split(rest, ~r/\n---[ \t]*(\n|\z)/, parts: 2),
         {:ok, fields} when is_map(fields) <- YamlElixir.read_from_string(front) do
      {:ok, fields, String.trim(body)}
    else
      [_unclosed] -> {:error, "opens its frontmatter with --- and never closes it"}
      {:ok, _other} -> {:error, "has frontmatter that isn't a set of keys"}
      {:error, error} -> {:error, "has frontmatter that isn't YAML: #{Exception.message(error)}"}
    end
  end

  defp split(text), do: {:ok, %{}, String.trim(text)}

  defp id(path, fields, org) do
    name = Map.get(fields, "name", path |> Path.basename() |> Path.rootname())

    case {Map.get(fields, "org", org), fields["user"]} do
      {^org, nil} ->
        {:ok, "#{org}/#{name}"}

      {^org, user} ->
        {:ok, "#{org}/@#{String.trim_leading(user, "@")}/#{name}"}

      {other, _user} ->
        {:error, "is in the org #{other}, and this deployment runs #{org}'s agents"}
    end
  end

  defp definition(fields, body, defaults) do
    defaults
    |> Map.merge(Map.drop(fields, ~w(name org user)))
    |> instructions(body)
  end

  defp instructions(definition, ""), do: definition
  defp instructions(definition, body), do: Map.put(definition, "instructions", body)
end

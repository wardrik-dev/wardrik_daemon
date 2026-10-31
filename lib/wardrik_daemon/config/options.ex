defmodule WardrikDaemon.Config.Options do
  @moduledoc """
  Turns a section of `config.yaml` into options, checked against their `NimbleOptions` schema.

  Each key becomes the option of the same name. A value takes the option's type where YAML can't
  say it:

    * a string names one of an `{:in, [...]}` option's atoms, as `flow: device`.
    * a map is a keyword list where the option takes one, as `req_options: {retry: false}`.

  Errors name the key's place in `config.yaml`, as `oauth.providers.google: unknown options ...`.

  A key becomes an atom only if one of that name exists, so load the modules that name a
  section's options first, with `loaded/1`.
  """

  @doc "Loads `modules`, so the options they name exist as atoms. `Req.Steps` names `Req`'s."
  @spec loaded([module()]) :: :ok
  def loaded(modules), do: Enum.each(modules, &Code.ensure_loaded!/1)

  @doc """
  Returns `yaml`'s keys as `schema`'s options, with their values converted.

  `path` names the section, or is `nil` for the file's own keys. A key no option is named after is
  an error.
  """
  @spec convert(term(), keyword(), String.t() | nil) :: {:ok, keyword()} | {:error, String.t()}
  def convert(yaml, schema, path) when is_map(yaml) do
    collected(yaml, fn {key, value} ->
      with {:ok, option} <- option(key, schema, path),
           {:ok, value} <- value(schema[option], value, join(path, key)),
           do: {:ok, {option, value}}
    end)
  end

  def convert(_yaml, _schema, path), do: {:error, at(path, "is a map of options")}

  @doc "Converts `yaml` and checks it against `schema`. Returns the checked options, with their defaults."
  @spec validate(term(), keyword(), String.t() | nil) :: {:ok, keyword()} | {:error, String.t()}
  def validate(yaml, schema, path) do
    with {:ok, opts} <- convert(yaml, schema, path), do: checked(opts, schema, path)
  end

  @doc "Checks `opts` against `schema`, naming `path` in the error."
  @spec checked(keyword(), keyword() | NimbleOptions.t(), String.t() | nil) ::
          {:ok, keyword()} | {:error, String.t()}
  def checked(opts, schema, path) do
    case NimbleOptions.validate(opts, schema) do
      {:ok, opts} -> {:ok, opts}
      {:error, error} -> {:error, message(error, path)}
    end
  end

  @doc "Calls `build`, a library's constructor. Returns its error, naming `path`, if it raises one."
  @spec built((-> result), String.t()) :: {:ok, result} | {:error, String.t()} when result: term()
  def built(build, path) do
    {:ok, build.()}
  rescue
    error in NimbleOptions.ValidationError -> {:error, message(error, path)}
    error in ArgumentError -> {:error, at(path, Exception.message(error))}
  end

  @doc "Calls `read` with each name and value in `entries`. Returns each name with its result, or the first error."
  @spec each(map() | [{term(), term()}], (term(), term() -> {:ok, result} | {:error, String.t()})) ::
          {:ok, [{term(), result}]} | {:error, String.t()}
        when result: term()
  def each(entries, read) do
    collected(entries, fn {name, value} ->
      with {:ok, result} <- read.(name, value), do: {:ok, {name, result}}
    end)
  end

  defp collected(enumerable, read) do
    result =
      Enum.reduce_while(enumerable, {:ok, []}, fn entry, {:ok, done} ->
        case read.(entry) do
          {:ok, item} -> {:cont, {:ok, [item | done]}}
          error -> {:halt, error}
        end
      end)

    with {:ok, done} <- result, do: {:ok, Enum.reverse(done)}
  end

  @doc "Returns `schema`'s options without those `doc: false` hides or `managed` names."
  @spec public(keyword() | NimbleOptions.t(), [atom()]) :: keyword()
  def public(%NimbleOptions{schema: schema}, managed), do: public(schema, managed)

  def public(schema, managed),
    do: Enum.reject(schema, fn {key, spec} -> key in managed or spec[:doc] == false end)

  @doc "Returns `message` with `path` before it."
  @spec at(String.t() | nil, String.t()) :: String.t()
  def at(nil, message), do: message
  def at(path, message), do: "#{path}: #{message}"

  defp join(nil, key), do: key
  defp join(path, key), do: "#{path}.#{key}"

  defp message(%NimbleOptions.ValidationError{message: message, keys_path: keys_path}, path),
    do: at(Enum.reduce(keys_path, path, &join(&2, &1)), message)

  @doc "Returns the atom named `text`, or `text` if there's none. For a value an option takes as an atom."
  @spec atom(term()) :: atom() | term()
  def atom(text) when is_binary(text) do
    String.to_existing_atom(text)
  rescue
    ArgumentError -> text
  end

  def atom(other), do: other

  defp option(key, schema, path) do
    case atom(key) do
      option when is_atom(option) -> {:ok, option}
      _unknown -> unknown(key, schema, path)
    end
  end

  defp unknown(key, [], path), do: {:error, at(join(path, to_string(key)), "isn't an option")}

  defp unknown(key, schema, path),
    do:
      {:error,
       at(path, "unknown options [#{key}], valid options are: #{inspect(Keyword.keys(schema))}")}

  defp value(nil, value, _path), do: {:ok, value}

  defp value(spec, map, path) when is_map(map) do
    cond do
      Keyword.has_key?(spec, :keys) -> convert(map, spec[:keys], path)
      keyword?(spec[:type]) -> convert(map, [], path)
      true -> {:ok, map}
    end
  end

  defp value(spec, text, _path) when is_binary(text), do: {:ok, chosen(spec[:type], text)}
  defp value(_spec, value, _path), do: {:ok, value}

  defp keyword?(type) when type in [:keyword_list, :non_empty_keyword_list], do: true
  defp keyword?({:or, types}), do: Enum.any?(types, &keyword?/1)
  defp keyword?(_type), do: false

  defp chosen({:in, choices}, text),
    do: Enum.find(choices, text, &(is_atom(&1) and Atom.to_string(&1) == text))

  defp chosen({:or, types}, text), do: Enum.reduce(types, text, &chosen/2)
  defp chosen(_type, text), do: text
end

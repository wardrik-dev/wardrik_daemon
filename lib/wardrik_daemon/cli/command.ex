defmodule WardrikDaemon.CLI.Command do
  @moduledoc """
  One command `wardrik` takes, defined once for its help, its options and running it: its `name`,
  as `agent ls`, the `group` help lists it under, its `arguments` and `summary`, more `details`, the
  `switches` it takes, as `OptionParser` does, and how many arguments, `count`, as a number or
  `{least, :any}`. `run` takes the arguments, the switches and the `WardrikDaemon.CLI.Context`. A
  command `bin/wardrik` runs itself has none. `shortcut` is a shorter name it also takes, as `ls`.
  """

  @enforce_keys [:name, :group, :summary]
  defstruct [
    :name,
    :group,
    :summary,
    :run,
    :shortcut,
    arguments: "",
    details: [],
    switches: [],
    count: 0
  ]

  @type run() :: ([String.t()], map(), WardrikDaemon.CLI.Context.t() ->
                    :ok | {:error, String.t()})

  @type t() :: %__MODULE__{
          name: String.t(),
          group: String.t(),
          summary: String.t(),
          run: run() | nil,
          shortcut: String.t() | nil,
          arguments: String.t(),
          details: [String.t()],
          switches: keyword(),
          count: non_neg_integer() | {non_neg_integer(), :any}
        }

  @doc "Returns the words that name `command`."
  @spec words(t()) :: [String.t()]
  def words(%__MODULE__{name: name}), do: String.split(name)

  @doc "Says whether `command` takes `count` arguments."
  @spec takes?(t(), non_neg_integer()) :: boolean()
  def takes?(%__MODULE__{count: {least, :any}}, count), do: count >= least
  def takes?(%__MODULE__{count: expected}, count), do: count == expected

  @doc "Returns how `command` is typed, as `agent show AGENT [--json]`."
  @spec usage(t()) :: String.t()
  def usage(%__MODULE__{} = command) do
    [command.name, command.arguments, options(command.switches)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp options(switches) do
    Enum.map_join(switches, " ", fn
      {name, :boolean} -> "[--#{flag(name)}]"
      {name, _type} -> "[--#{flag(name)} #{name |> Atom.to_string() |> String.upcase()}]"
    end)
  end

  defp flag(name), do: name |> Atom.to_string() |> String.replace("_", "-")
end

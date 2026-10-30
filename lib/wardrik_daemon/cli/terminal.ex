defmodule WardrikDaemon.CLI.Terminal do
  @moduledoc """
  The terminal a command writes to: how wide it is, and whether it takes colour.

  It takes colour if standard output is a terminal, `NO_COLOR` isn't set and `TERM` isn't `dumb`.
  Otherwise, as through a pipe, it writes plain text 80 columns wide.
  """

  alias WardrikDaemon.Console.Ansi

  defstruct width: 80, colour?: false

  @type t() :: %__MODULE__{width: pos_integer(), colour?: boolean()}

  @doc "Returns the terminal standard output is, with `env`, the environment, saying whether it takes colour."
  @spec new(%{String.t() => String.t()}) :: t()
  def new(env) do
    case :io.columns() do
      {:ok, width} -> %__MODULE__{width: width, colour?: colour?(env)}
      {:error, _not_a_terminal} -> %__MODULE__{}
    end
  end

  @doc "Writes `data` and a newline, styled if the terminal takes colour."
  @spec puts(t(), Owl.Data.t()) :: :ok
  def puts(%__MODULE__{colour?: colour?}, data), do: IO.puts(Ansi.chardata(data, colour?))

  @doc "Writes each of `lines`."
  @spec lines(t(), [Owl.Data.t()]) :: :ok
  def lines(terminal, lines), do: Enum.each(lines, &puts(terminal, &1))

  defp colour?(%{"NO_COLOR" => _set}), do: false
  defp colour?(%{"TERM" => "dumb"}), do: false
  defp colour?(_env), do: true
end

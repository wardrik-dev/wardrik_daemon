defmodule WardrikDaemon.CLI.Table do
  @moduledoc "Prints rows as columns, each as wide as its widest cell, under a faint header."

  alias WardrikDaemon.CLI.Context

  @doc "Writes `answer` as JSON if the command was given `--json`. Otherwise prints it as `print/4` does."
  @spec show(Context.t(), term(), [String.t()], [[term()]], String.t()) :: :ok
  def show(cx, answer, header, rows, empty),
    do: Context.show(cx, answer, fn _answer -> print(cx, header, rows, empty) end)

  @doc "Prints `rows` under `header`, or `empty` if there are none. A `nil` cell is empty."
  @spec print(Context.t(), [String.t()], [[term()]], String.t()) :: :ok
  def print(cx, _header, [], empty), do: Context.puts(cx, Owl.Data.tag(empty, :light_black))

  def print(cx, header, rows, _empty) do
    rows = Enum.map(rows, fn row -> Enum.map(row, &to_string(&1 || "")) end)
    widths = Enum.zip_with([header | rows], &widest/1)
    Context.puts(cx, Owl.Data.tag(line(header, widths), [:faint, :light_black]))
    Enum.each(rows, &Context.puts(cx, line(&1, widths)))
  end

  @doc "Prints `pairs` of a label and a value, one a line. Leaves out those with no value."
  @spec pairs(Context.t(), [{String.t(), term()}]) :: :ok
  def pairs(cx, pairs) do
    shown = for {label, value} <- pairs, value not in [nil, "", []], do: {label, to_string(value)}

    width =
      shown |> Enum.map(fn {label, _value} -> String.length(label) end) |> Enum.max(fn -> 0 end)

    Enum.each(shown, fn {label, value} ->
      Context.puts(cx, [
        Owl.Data.tag(String.pad_trailing(label, width), :light_black),
        "  ",
        value
      ])
    end)
  end

  defp widest(column), do: column |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)

  defp line(row, widths) do
    row
    |> Enum.zip(widths)
    |> Enum.map_join("  ", fn {cell, width} -> String.pad_trailing(cell, width) end)
    |> String.trim_trailing()
  end
end

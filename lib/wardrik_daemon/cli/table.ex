defmodule WardrikDaemon.CLI.Table do
  @moduledoc "Prints rows as columns, each as wide as its widest cell."

  @doc "Prints `rows`, a list of lists of cells, where `nil` is empty."
  @spec print([[term()]]) :: :ok
  def print(rows) do
    rows = Enum.map(rows, fn row -> Enum.map(row, &to_string(&1 || "")) end)
    widths = Enum.zip_with(rows, &widest/1)
    Enum.each(rows, &IO.puts(line(&1, widths)))
  end

  defp widest(column), do: column |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)

  defp line(row, widths) do
    row
    |> Enum.zip(widths)
    |> Enum.map_join("  ", fn {cell, width} -> String.pad_trailing(cell, width) end)
    |> String.trim_trailing()
  end
end

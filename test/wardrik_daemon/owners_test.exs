defmodule WardrikDaemon.OwnersTest do
  use ExUnit.Case, async: true

  test "only Wardrik.Owners reads an owner's org or person" do
    readers =
      for path <- Path.wildcard("lib/**/*.ex"),
          File.read!(path) =~ ~r{"/@"|String\.split\(owner},
          do: path

    assert readers == []
  end
end

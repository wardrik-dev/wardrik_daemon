defmodule WardrikDaemon.OwnersTest do
  use ExUnit.Case, async: true

  alias WardrikDaemon.Owners

  test "only WardrikDaemon.Owners reads an owner's org or person" do
    readers =
      for path <- Path.wildcard("lib/**/*.ex"),
          path != "lib/wardrik_daemon/owners.ex",
          File.read!(path) =~ ~r{"/@"|String\.split\((owner|id)},
          do: path

    assert readers == []
  end

  test "reads an agent's owner from its ID, and nothing that isn't one" do
    assert Owners.owner("acme/triage") == {:ok, "acme"}
    assert Owners.owner("acme/@jon/notes") == {:ok, "acme/@jon"}
    assert Owners.owner("acme/triage/C1-1696.1234") == {:ok, "acme"}
    assert Owners.owner("acme/@jon/notes/C1") == {:ok, "acme/@jon"}

    for id <- [
          "acme",
          "acme/",
          "/triage",
          "acme/@/notes",
          "acme/*",
          "acme/t?",
          "../globex/triage",
          "acme/a/b/c",
          "acme/@jon/a/b/c",
          "acme:x/triage",
          ""
        ],
        do: assert(Owners.owner(id) == :error, id)

    assert Owners.chain("acme/@jon") == ["acme/@jon", "acme", "deployment"]
    assert Owners.chain("acme") == ["acme", "deployment"]
  end
end

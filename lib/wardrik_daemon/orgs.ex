defmodule WardrikDaemon.Orgs do
  @moduledoc """
  Says which orgs the daemon runs agents for, and the policies each is held to. It's the daemon's
  `Wardrik.Orgs`.

  Those orgs are the deployment's own `org` and each one `config.yaml`'s `orgs` names. Any other
  org is refused: nothing is defined, started or kept for it.

  Each org is held to `"*"`'s policy, then its own, both from `policies/`. An org whose policy
  isn't in `policies/` runs none of its agents.

  A policy's budget is shared by all of an org's agents. Each org spends `"*"`'s budget apart from
  the others. A budget `per: turn` stays each agent's own, since a turn is one agent's.
  """

  @behaviour Wardrik.Orgs

  alias Wardrik.Error
  alias Wardrik.OrgSettings

  @impl Wardrik.Orgs
  def settings(org, %{org: own, orgs: orgs, policies: policies}) do
    if org == own or Map.has_key?(orgs, org),
      do: held(org, names(orgs, org), policies),
      else: {:error, Error.new(:not_found, "There's no org #{org} here: #{declared(own, orgs)}.")}
  end

  defp names(orgs, org) do
    [orgs["*"], orgs[org]]
    |> Enum.map(&(&1 && &1.policy))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp held(org, names, policies) do
    case Enum.reject(names, &Map.has_key?(policies, &1)) do
      [] ->
        split = Enum.map(names, &pooled(&1, Map.fetch!(policies, &1)))

        ceilings =
          for {name, _policy, budget} <- split, budget != nil, into: %{}, do: {name, budget}

        {:ok, %OrgSettings{policy: Enum.map(split, &elem(&1, 1)), ceilings: ceilings}}

      [name | _rest] ->
        {:error,
         Error.new(
           :invalid_request,
           "#{org} is held to the policy #{name}, which policies/ doesn't hold, so its agents don't run."
         )}
    end
  end

  defp pooled(name, %WardrikPolicy{budget: %WardrikPolicy.Budget{per: per} = budget} = policy)
       when per != :turn,
       do:
         {name, %{policy | budget: nil},
          budget |> Map.from_struct() |> Enum.reject(&nil_value?/1)}

  defp pooled(name, policy), do: {name, policy, nil}

  defp nil_value?({_key, value}), do: value in [nil, []]

  defp declared(own, orgs) do
    named = Enum.sort([own | Map.keys(orgs) -- ["*"]])
    "config.yaml declares #{Enum.join(Enum.uniq(named), ", ")}"
  end
end

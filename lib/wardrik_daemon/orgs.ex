defmodule WardrikDaemon.Orgs do
  @moduledoc """
  The orgs `config.yaml` declares, as `Wardrik.Orgs`: the deployment's own `org`, and those `orgs`
  names. Every other org is refused, so nothing is defined, started or kept for it.

  An org is held to `"*"`'s policy and then its own, each from `policies/`. A policy's budget is
  the org's, which all its agents spend from together, as a ceiling by the policy's name; each org
  spends `"*"`'s apart. A budget per turn stays each agent's own, since a turn is one agent's. An
  org whose policy `policies/` doesn't hold runs none of its agents.
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

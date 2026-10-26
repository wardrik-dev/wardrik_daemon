defmodule WardrikDaemon.CLI do
  @moduledoc """
  The `wardrik` command. Each command runs an operation on the daemon over its HTTP API, with the
  token the daemon wrote for it as it started, and prints what it answers. `serve`, `start`, `stop`
  and `logs` belong to the `bin/wardrik` script, which runs the daemon itself.

  An agent is named by its ID, as `acme/triage`, or without the deployment's org, as `triage` or
  `@jon/notes`.
  """

  alias WardrikDaemon.CLI.Access
  alias WardrikDaemon.CLI.Admin
  alias WardrikDaemon.CLI.Agents
  alias WardrikDaemon.CLI.Ask
  alias WardrikDaemon.CLI.Context
  alias WardrikDaemon.CLI.Init

  @help """
  Usage: wardrik COMMAND

  Run the daemon:
    serve                  run it here, in the foreground
    start | stop           run it in the background, or stop it
    status                 say whether it runs, and what on
    logs                   show what it logged
    service install        run it as a systemd user service
    init [--org ORG]       write config.yaml and a first agent
    doctor                 check what the daemon reads, running or not
    reload                 read the agent files again; doctor says which don't read

  Talk to agents:
    ask AGENT MESSAGE      ask, and print the answer as it comes
    ls                     list the agents
    show AGENT             say what an agent is, and what it does now
    triggers AGENT         list an agent's triggers
    history AGENT          print an agent's conversation
    agent rm AGENT         remove an agent, and everything it had

  Decide:
    parked                 list the calls agents wait on a person for
    approve AGENT CALL [--note TEXT]
    deny AGENT CALL [--reason TEXT]

  Tokens and secrets:
    token create NAME --resource PATTERN --role ROLE[,ROLE] [--expires 30d] [--policy NAME]
    token list | token revoke ID
    vault put NAME [--org ORG | --user USER]    the value is read from stdin
    vault ls [--org ORG | --user USER]
    vault rm NAME [--org ORG | --user USER]
    audit                  list what people changed
  """

  @switches [
    org: :string,
    user: :string,
    note: :string,
    reason: :string,
    resource: :keep,
    role: :string,
    expires: :string,
    policy: :string,
    model: :string
  ]

  @doc "Runs the command `argv` names in a VM of its own, as `bin/wardrik` does, and halts with its status."
  @spec halt([String.t()]) :: no_return()
  def halt(argv) do
    {:ok, _started} = Application.ensure_all_started([:req, :yaml_elixir])
    System.halt(main(argv))
  end

  @doc "Runs the command `argv` names, and returns the status to exit with. Takes `:env`, the environment."
  @spec main([String.t()], keyword()) :: 0 | 1
  def main(argv, opts \\ []) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)
    {flags, args, invalid} = OptionParser.parse(argv, strict: @switches)

    case {invalid, run(args, Map.new(flags), Context.new(env))} do
      {[{flag, _value} | _rest], _ran} -> failed("#{flag} isn't an option of that command.")
      {[], :ok} -> 0
      {[], {:error, why}} -> failed(why)
    end
  end

  defp failed(why) do
    IO.puts(:stderr, "wardrik: " <> why)
    1
  end

  defp run([], _flags, _cx), do: help()
  defp run(["help" | _rest], _flags, _cx), do: help()

  defp run(["init"], flags, cx) do
    model = Map.get(flags, :model, "anthropic:claude-haiku-4-5")

    for {path, done} <- Init.run(cx.dirs, Map.get(flags, :org, "default"), model),
        do: IO.puts("#{if done == :written, do: "Wrote", else: "Kept"} #{path}")

    :ok
  end

  defp run(["ask", agent | words], _flags, cx) when words != [] do
    with {:ok, client} <- Context.client(cx),
         do: Ask.run(client, Context.agent(cx, agent), Enum.join(words, " "))
  end

  defp run(args, flags, cx) do
    with :none <- Agents.run(args, flags, cx),
         :none <- Access.run(args, flags, cx),
         :none <- Admin.run(args, flags, cx),
         do: unknown(args)
  end

  defp unknown([command | _rest]),
    do: {:error, "#{command} isn't a command, or takes other arguments. See wardrik help."}

  defp help, do: IO.write(@help)
end

defmodule WardrikDaemon.Test do
  @moduledoc "Writes a daemon's files under a test's own directory, and starts it there."

  import ExUnit.Assertions, only: [assert_receive: 2]
  import ExUnit.Callbacks, only: [start_supervised!: 1]

  @model "anthropic:claude-haiku-4-5"

  def model, do: @model

  def dirs(context) do
    root = Path.join(System.tmp_dir!(), "wardrik_daemon #{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)

    env = %{
      "HOME" => root,
      "WARDRIK_CONFIG_DIR" => Path.join(root, "config"),
      "WARDRIK_DATA_HOME" => Path.join(root, "data"),
      "WARDRIK_STATE_DIR" => Path.join(root, "state")
    }

    Map.merge(context, %{root: root, env: env})
  end

  def write(%{env: env}, name, text) do
    path = Path.join(env["WARDRIK_CONFIG_DIR"], name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text)
    path
  end

  def free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  def start_daemon(context) do
    name = :"wardrik #{context.test}"
    store = WardrikStore.ETS.new(name: :"store #{context.test}")
    ref = :telemetry_test.attach_event_handlers(self(), [[:wardrik_daemon, :started]])

    {_pid, log} =
      ExUnit.CaptureLog.with_log(fn ->
        pid =
          start_supervised!(
            {WardrikDaemon.Server,
             env: context.env,
             name: name,
             store: store,
             capabilities: [echo: WardrikDaemon.Test.Tools]}
          )

        assert_receive({[:wardrik_daemon, :started], ^ref, _measurements, _meta}, 5_000)
        pid
      end)

    owner = Wardrik.as(name, "acme/@jon", roles: [:owner], resources: ["*"])
    Map.merge(context, %{wardrik: name, owner: owner, log: log})
  end
end

defmodule WardrikDaemon.Test.Tools do
  @moduledoc "A capability with one tool, `echo`."
  @behaviour WardrikCore.Capability

  @impl WardrikCore.Capability
  def tools(_context, _opts) do
    [
      WardrikCore.Tool.new!(
        name: "echo",
        description: "Echoes text",
        schema: [text: [type: :string]],
        run: fn args, _context -> {:ok, Map.get(args, :text, "")} end
      )
    ]
  end
end

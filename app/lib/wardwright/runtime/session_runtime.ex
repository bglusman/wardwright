defmodule Wardwright.Runtime.SessionRuntime do
  @moduledoc false

  use GenServer

  alias Wardwright.Runtime.Events
  alias Wardwright.PolicySandbox.Dune, as: DuneSandbox

  @max_dune_sessions 64

  def start_link(opts) do
    model_id = Keyword.fetch!(opts, :model_id)
    version = Keyword.fetch!(opts, :version)
    session_id = Keyword.fetch!(opts, :session_id)

    GenServer.start_link(__MODULE__, {model_id, version, session_id},
      name: via(model_id, version, session_id)
    )
  end

  def child_spec(opts) do
    model_id = Keyword.fetch!(opts, :model_id)
    version = Keyword.fetch!(opts, :version)
    session_id = Keyword.fetch!(opts, :session_id)

    %{
      id: {__MODULE__, model_id, version, session_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5_000,
      type: :worker
    }
  end

  def via(model_id, version, session_id) do
    {:via, Registry, {Wardwright.Runtime.Registry, {:session, model_id, version, session_id}}}
  end

  def record(pid, type, fields \\ %{}) when is_pid(pid) and is_binary(type) and is_map(fields) do
    GenServer.call(pid, {:record, type, fields})
  end

  def eval_dune_snippet(pid, source, input, config, eval_opts \\ [])
      when is_pid(pid) and is_binary(source) and is_map(config) and is_list(eval_opts) do
    GenServer.call(pid, {:eval_dune_snippet, source, input, config, eval_opts}, :infinity)
  end

  def status(pid), do: GenServer.call(pid, :status)

  @impl true
  def init({model_id, version, session_id}) do
    state = %{
      model_id: model_id,
      version: version,
      session_id: session_id,
      sequence: 0,
      event_count: 0,
      started_at: System.system_time(:second),
      last_event: nil,
      dune_sessions: %{}
    }

    {:ok, state, {:continue, :publish_started}}
  end

  @impl true
  def handle_continue(:publish_started, state) do
    {:noreply, publish(state, "session.started", %{})}
  end

  @impl true
  def handle_call({:record, type, fields}, _from, state) do
    state = publish(state, type, fields)
    {:reply, state.last_event, state}
  end

  def handle_call({:eval_dune_snippet, source, input, config, eval_opts}, _from, state) do
    now = now_ms()
    state = prune_dune_sessions(state, now)
    {session, metadata} = dune_session_for(state, config, now)
    {session, result} = DuneSandbox.eval_snippet_in_session(source, input, session, eval_opts)

    dune_sessions =
      state.dune_sessions
      |> Map.put(config.key, %{
        session: session,
        ttl_ms: config.ttl_ms,
        updated_at_ms: now
      })
      |> trim_oldest_dune_sessions()

    metadata = %{
      metadata
      | model_id: state.model_id,
        version: state.version,
        session_id: state.session_id
    }

    {:reply, {:ok, {result, metadata}}, %{state | dune_sessions: dune_sessions}}
  end

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       "model_id" => state.model_id,
       "version" => state.version,
       "session_id" => state.session_id,
       "pid" => inspect(self()),
       "started_at" => state.started_at,
       "event_count" => state.event_count,
       "last_event" => state.last_event
     }, state}
  end

  defp dune_session_for(_state, %{reset?: true} = config, _now) do
    {Dune.Session.new(), dune_metadata(config, "reset", false)}
  end

  defp dune_session_for(state, config, now) do
    case Map.get(state.dune_sessions, config.key) do
      nil ->
        {Dune.Session.new(), dune_metadata(config, "new", false)}

      %{session: session, updated_at_ms: updated_at, ttl_ms: ttl_ms}
      when now - updated_at <= ttl_ms ->
        {session, dune_metadata(config, "reused", true)}

      _expired ->
        {Dune.Session.new(), dune_metadata(config, "expired", false)}
    end
  end

  defp dune_metadata(config, status, reused?) do
    %{
      key: config.key,
      status: status,
      reused?: reused?,
      ttl_ms: config.ttl_ms,
      model_id: nil,
      version: nil,
      session_id: nil
    }
  end

  defp prune_dune_sessions(state, now) do
    dune_sessions =
      Map.reject(state.dune_sessions, fn {_key, %{updated_at_ms: updated_at, ttl_ms: ttl_ms}} ->
        now - updated_at > ttl_ms
      end)

    %{state | dune_sessions: dune_sessions}
  end

  defp trim_oldest_dune_sessions(dune_sessions)
       when map_size(dune_sessions) <= @max_dune_sessions,
       do: dune_sessions

  defp trim_oldest_dune_sessions(dune_sessions) do
    dune_sessions
    |> Enum.sort_by(fn {_key, %{updated_at_ms: updated_at}} -> updated_at end)
    |> Enum.drop(map_size(dune_sessions) - @max_dune_sessions)
    |> Map.new()
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp publish(state, type, fields) do
    sequence = state.sequence + 1

    event =
      fields
      |> stringify_keys()
      |> Map.merge(%{
        "type" => type,
        "model_id" => state.model_id,
        "version" => state.version,
        "session_id" => state.session_id,
        "sequence" => sequence,
        "created_at" => System.system_time(:second)
      })

    topics = [
      Events.topic(:models),
      Events.topic(:model, state.model_id, state.version),
      Events.topic(:session, state.model_id, state.version, state.session_id)
    ]

    Events.publish_many(topics, event)

    %{state | sequence: sequence, event_count: state.event_count + 1, last_event: event}
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end

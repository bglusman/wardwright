defmodule Wardwright.Runtime.ModelRuntime do
  @moduledoc false

  use GenServer

  alias Wardwright.ModelSkyline.Lease
  alias Wardwright.ModelSkyline.WorkUnit.RuntimeKey
  alias Wardwright.Runtime.Events

  @max_model_skyline_pins 1_024
  @max_model_skyline_pins_per_principal 64

  def start_link(opts) do
    model_id = Keyword.fetch!(opts, :model_id)
    version = Keyword.fetch!(opts, :version)

    GenServer.start_link(__MODULE__, {model_id, version}, name: via(model_id, version))
  end

  def child_spec(opts) do
    model_id = Keyword.fetch!(opts, :model_id)
    version = Keyword.fetch!(opts, :version)

    %{
      id: {__MODULE__, model_id, version},
      restart: :permanent,
      shutdown: 5_000,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  def via(model_id, version), do: {:via, Registry, {Wardwright.Runtime.Registry, {:model, model_id, version}}}

  def model_skyline_pin(pid, %RuntimeKey{} = work_unit_key, %DateTime{} = now) when is_pid(pid) do
    GenServer.call(pid, {:model_skyline_pin, work_unit_key, now})
  end

  def put_model_skyline_pin(pid, %RuntimeKey{} = work_unit_key, %Lease{} = lease, %DateTime{} = now) when is_pid(pid) do
    GenServer.call(pid, {:put_model_skyline_pin, work_unit_key, lease, now})
  end

  def status(pid), do: status(pid, DateTime.utc_now())
  def status(pid, %DateTime{} = now), do: GenServer.call(pid, {:status, now})

  @impl true
  def init({model_id, version}) do
    state = %{
      model_id: model_id,
      model_skyline_pins: %{},
      started_at: System.system_time(:second),
      version: version
    }

    event = %{
      "model_id" => model_id,
      "started_at" => state.started_at,
      "type" => "model.started",
      "version" => version
    }

    Events.publish_many([Events.topic(:models), Events.topic(:model, model_id, version)], event)

    {:ok, state}
  end

  @impl true
  def handle_call({:model_skyline_pin, work_unit_key, now}, _from, state) do
    pins = prune_expired_pins(state.model_skyline_pins, now)

    case Map.fetch(pins, work_unit_key) do
      {:ok, lease} -> {:reply, {:ok, lease}, %{state | model_skyline_pins: pins}}
      :error -> {:reply, :missing, %{state | model_skyline_pins: pins}}
    end
  end

  def handle_call({:put_model_skyline_pin, work_unit_key, lease, now}, _from, state) do
    pins = prune_expired_pins(state.model_skyline_pins, now)

    case Map.fetch(pins, work_unit_key) do
      {:ok, existing} ->
        {:reply, {:ok, existing}, %{state | model_skyline_pins: pins}}

      :error when map_size(pins) >= @max_model_skyline_pins ->
        {:reply, {:error, :selection_pin_capacity_exceeded}, %{state | model_skyline_pins: pins}}

      :error ->
        if principal_pin_count(pins, work_unit_key.principal_digest) >=
             @max_model_skyline_pins_per_principal do
          {:reply, {:error, :selection_principal_pin_capacity_exceeded}, %{state | model_skyline_pins: pins}}
        else
          pins = Map.put(pins, work_unit_key, lease)
          {:reply, {:ok, lease}, %{state | model_skyline_pins: pins}}
        end
    end
  end

  def handle_call({:status, now}, _from, state) do
    pins = prune_expired_pins(state.model_skyline_pins, now)

    {:reply,
     %{
       "model_id" => state.model_id,
       "model_skyline_pin_count" => map_size(pins),
       "pid" => inspect(self()),
       "started_at" => state.started_at,
       "version" => state.version
     }, %{state | model_skyline_pins: pins}}
  end

  defp prune_expired_pins(pins, now) do
    Map.reject(pins, fn {_key, lease} -> DateTime.compare(lease.valid_until, now) != :gt end)
  end

  defp principal_pin_count(pins, principal_digest) do
    Enum.count(pins, fn {key, _lease} -> key.principal_digest == principal_digest end)
  end
end

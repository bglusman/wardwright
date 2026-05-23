defmodule WardwrightWeb.AdapterRequestContext do
  @moduledoc false

  import Plug.Conn

  alias Wardwright.AgentAdapters.Identity
  alias Wardwright.AgentAdapters.OmpPack
  alias WardwrightWeb.RequestContext

  @adapter_id_key "adapter_id"
  @adapter_version_key "adapter_version"
  @client_kind_key "client_kind"
  @recording_mode_key "recording_mode"
  @runtime_key "runtime"
  @target_key "target"
  @verification_state_key "verification_state"
  @verified_key "verified"
  @workspace_fingerprint_key "workspace_fingerprint"

  @adapted_agents_key "adapted_agents"
  @default_key "default"
  @generic_clients_key "generic_clients"
  @mode_key "mode"
  @recording_key "recording"
  @vcr_key "vcr"

  @auto "auto"
  @full_session "full_session"
  @generic "generic"
  @manual "manual"
  @metadata_only "metadata_only"
  @verified "verified"
  @installed_unverified "installed_unverified"

  @adapter_id_header "x-wardwright-adapter-id"
  @adapter_identity_header "x-wardwright-adapter-identity"
  @adapter_runtime_header "x-wardwright-adapter-runtime"
  @adapter_target_header "x-wardwright-adapter-target"
  @recording_header "x-wardwright-recording"
  @workspace_fingerprint_header "x-wardwright-workspace-fingerprint"
  @workspace_fingerprint_env "WARDWRIGHT_WORKSPACE_FINGERPRINT"

  def from_conn(conn, config) do
    with {:ok, adapter} <- adapter_from_conn(conn),
         {:ok, explicit_recording_mode} <- explicit_recording_mode(conn) do
      recording_mode = recording_mode(config, adapter, explicit_recording_mode)

      {:ok,
       %{
         adapter: adapter,
         recording_mode: recording_mode,
         vcr_mode: vcr_mode(config, recording_mode, explicit_recording_mode)
       }}
    end
  end

  def apply_recording(config, %{vcr_mode: vcr_mode}) do
    vcr =
      config
      |> Map.get(@vcr_key, %{})
      |> Map.put(@mode_key, vcr_mode)

    Map.put(config, @vcr_key, vcr)
  end

  def caller_adapter(nil, _context), do: nil

  def caller_adapter(adapter, context) when is_map(adapter) do
    Map.put(adapter, @recording_mode_key, context.recording_mode)
  end

  defp adapter_from_conn(conn) do
    case header(conn, @adapter_identity_header) do
      nil -> declared_adapter_from_conn(conn)
      encoded_identity -> verified_adapter_from_identity(conn, encoded_identity)
    end
  end

  defp verified_adapter_from_identity(conn, encoded_identity) do
    with {:ok, identity} <- decode_identity(encoded_identity),
         {:ok, workspace_fingerprint} <- expected_workspace_fingerprint(conn),
         {:ok, claims} <-
           Identity.validate(identity,
             adapter_id: OmpPack.adapter_id(),
             runtime: "omp",
             target: "omp",
             workspace_fingerprint: workspace_fingerprint
           ) do
      {:ok,
       %{
         @adapter_id_key => Map.get(claims, @adapter_id_key),
         @adapter_version_key => Map.get(claims, @adapter_version_key),
         @client_kind_key => "adapter",
         @runtime_key => Map.get(claims, @runtime_key),
         @target_key => Map.get(claims, @target_key),
         @verification_state_key => @verified,
         @verified_key => true,
         @workspace_fingerprint_key => Map.get(claims, @workspace_fingerprint_key)
       }}
    else
      {:error, :wrong_workspace} ->
        {:error, :adapter_identity, 403, "adapter identity is for a different workspace",
         "adapter_identity_wrong_workspace"}

      {:error, :expired} ->
        {:error, :adapter_identity, 401, "adapter identity is expired", "adapter_identity_expired"}

      {:error, :missing_secret} ->
        {:error, :adapter_identity, 503, "adapter identity signing secret is not configured",
         "adapter_identity_secret_missing"}

      {:error, _reason} ->
        {:error, :adapter_identity, 401, "adapter identity is invalid", "adapter_identity_invalid"}
    end
  end

  defp declared_adapter_from_conn(conn) do
    case header(conn, @adapter_id_header) do
      nil ->
        {:ok, nil}

      adapter_id ->
        {:ok,
         %{
           @adapter_id_key => adapter_id,
           @client_kind_key => "adapter",
           @runtime_key => header(conn, @adapter_runtime_header) || "",
           @target_key => header(conn, @adapter_target_header) || "",
           @verification_state_key => @installed_unverified,
           @verified_key => false
         }}
    end
  end

  defp recording_mode(config, adapter, explicit_recording_mode) do
    recording = Map.get(config, @recording_key, %{})
    client_kind = if is_map(adapter), do: "adapter", else: @generic
    adapter_state = if is_map(adapter), do: Map.get(adapter, @verification_state_key, ""), else: ""

    :wardwright@adapter_core.recording_mode(
      Map.get(recording, @default_key, @manual),
      Map.get(recording, @adapted_agents_key, @auto),
      Map.get(recording, @generic_clients_key, @manual),
      client_kind,
      adapter_state,
      explicit_recording_mode || ""
    )
  end

  defp vcr_mode(_config, @auto, _explicit_recording_mode), do: @full_session
  defp vcr_mode(_config, @manual, @manual), do: @metadata_only

  defp vcr_mode(config, _recording_mode, _explicit_recording_mode) do
    get_in(config, [@vcr_key, @mode_key]) || @metadata_only
  end

  defp explicit_recording_mode(conn) do
    case header(conn, @recording_header) do
      nil ->
        {:ok, nil}

      @auto ->
        {:ok, @auto}

      @manual ->
        {:ok, @manual}

      _value ->
        {:error, :adapter_identity, 400, "x-wardwright-recording must be auto or manual", "invalid_recording_mode"}
    end
  end

  defp decode_identity(encoded_identity) do
    case JSON.decode(encoded_identity) do
      {:ok, identity} when is_map(identity) -> {:ok, identity}
      _value -> {:error, :malformed}
    end
  end

  defp required_header(conn, name) do
    case header(conn, name) do
      nil -> {:error, :malformed}
      value -> {:ok, value}
    end
  end

  defp expected_workspace_fingerprint(conn) do
    case RequestContext.blank_to_nil(Application.get_env(:wardwright, :adapter_workspace_fingerprint)) ||
           RequestContext.blank_to_nil(System.get_env(@workspace_fingerprint_env)) do
      nil -> required_header(conn, @workspace_fingerprint_header)
      workspace_fingerprint -> {:ok, workspace_fingerprint}
    end
  end

  defp header(conn, name) do
    conn
    |> get_req_header(name)
    |> List.first()
    |> RequestContext.metadata_string()
    |> RequestContext.blank_to_nil()
  end
end

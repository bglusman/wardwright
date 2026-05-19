defmodule WardwrightWeb.LustreWorkbenchSocket do
  @moduledoc false

  @behaviour Phoenix.Socket.Transport

  require Logger

  @dialyzer {:nowarn_function, subscribe: 1}
  @dialyzer {:nowarn_function, unsubscribe: 2}
  @dialyzer {:nowarn_function, parse_runtime_message: 1}

  @impl true
  def child_spec(_opts), do: :ignore

  @impl true
  def connect(state) do
    connect_info = Map.get(state, :connect_info, %{})

    if authorized?(connect_info) do
      {:ok, state}
    else
      :error
    end
  end

  @impl true
  def init(state) do
    with {:ok, component} <-
           :wardwright@lustre_admin.component() |> :lustre.start_server_component(initial_flags(state)) do
      subject = subscribe(component)

      {:ok,
       state
       |> Map.put(:component, component)
       |> Map.put(:subject, subject)}
    end
  end

  defp initial_flags(%{params: %{"model" => model, "page" => "model_access"}}) when is_binary(model),
    do: "model_access:" <> model

  defp initial_flags(%{params: %{"page" => "model_access"}}), do: "model_access"

  defp initial_flags(_state), do: "workbench"

  @impl true
  def handle_in({json, _opts}, state) when is_binary(json) do
    case parse_runtime_message(json) do
      {:ok, runtime_message} ->
        :lustre.send(state.component, runtime_message)

      {:error, errors} ->
        Logger.debug("ignored invalid Lustre runtime message errors=#{inspect(errors)}")
    end

    {:ok, state}
  end

  @impl true
  def handle_info({_ref, message}, state) when is_tuple(message) do
    json =
      message
      |> :lustre@server_component.client_message_to_json()
      |> json_to_string()

    {:push, {:text, json}, state}
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    if state[:component] && state[:subject] do
      unsubscribe(state.component, state.subject)
      :lustre.send(state.component, :lustre.shutdown())
    end

    :ok
  end

  defp subscribe(component) do
    subject = {:subject, self(), make_ref()}

    :lustre.send(component, :lustre@server_component.register_subject(subject))

    subject
  end

  defp unsubscribe(component, subject) do
    :lustre.send(component, :lustre@server_component.deregister_subject(subject))
  end

  defp authorized?(connect_info) do
    WardwrightWeb.ProtectedAccess.authorized_session?(Map.get(connect_info, :session)) or
      WardwrightWeb.ProtectedAccess.authorized_peer_and_headers?(
        peer_ip(connect_info),
        admin_headers(connect_info)
      )
  end

  defp peer_ip(%{peer_data: %{address: address}}), do: address
  defp peer_ip(_connect_info), do: nil

  defp admin_headers(connect_info) do
    x_headers = Map.get(connect_info, :x_headers, [])

    case Map.get(connect_info, :auth_token) do
      token when is_binary(token) and token != "" ->
        [{"authorization", "Bearer " <> token} | x_headers]

      _token ->
        x_headers
    end
  end

  defp parse_runtime_message(json) do
    {_, transformer} = :lustre@server_component.runtime_message_decoder()
    {data, errors} = transformer.(Jason.decode!(json))

    case errors do
      [] -> {:ok, data}
      [_ | _] -> {:error, errors}
    end
  rescue
    error -> {:error, [Exception.message(error)]}
  end

  defp json_to_string(json) when is_binary(json), do: json
  defp json_to_string(json) when is_list(json), do: List.to_string(json)
end

defmodule WardwrightWeb.LustreModelAccessData do
  @moduledoc false

  def default_model_id do
    Wardwright.current_config()
    |> Wardwright.model_id()
  end

  def model_options do
    Wardwright.model_summaries()
    |> Enum.map(fn model ->
      {
        model["id"] || "",
        model["description"] || "",
        model["route_type"] || "",
        if(model["requires_api_key"], do: "keyed", else: "unkeyed")
      }
    end)
  end

  def access_summary(model_id) do
    config = selected_config(model_id)
    model = config["model_id"] || model_id || default_model_id()
    requires_api_key = Wardwright.model_requires_api_key?(config)
    unkeyed_access = Wardwright.unkeyed_model_access(config)

    {model, requires_api_key, unkeyed_access, length(Wardwright.ModelApiKeyStore.list(model))}
  end

  def key_options(model_id) do
    model_id
    |> selected_config()
    |> Map.get("model_id")
    |> Wardwright.ModelApiKeyStore.list()
    |> Enum.map(fn key ->
      {
        key["id"] || "",
        key["label"] || "",
        key["prefix"] || "",
        key["created_at"] || ""
      }
    end)
  end

  def create_key(model_id, label) do
    model = selected_model_id(model_id)

    case Wardwright.ModelApiKeyStore.create(model, label) do
      {:ok, key} ->
        {true, "Copy this key now. Wardwright stores only a hash and will not show it again.", key["key"] || ""}

      _error ->
        {false, "Could not create API key.", ""}
    end
  end

  def revoke_key(id) do
    case Wardwright.ModelApiKeyStore.revoke(id) do
      :ok -> {true, "API key revoked."}
      _error -> {false, "Could not revoke API key."}
    end
  end

  def save_access(model_id, requires_api_key, unkeyed_model_access) do
    config = selected_config(model_id)

    updated_config =
      config
      |> Map.put("requires_api_key", requires_api_key)
      |> Map.put("auth", %{"unkeyed_model_access" => unkeyed_model_access})

    case Wardwright.put_model_config(updated_config) do
      {:ok, _config} -> {true, "Model access saved."}
      {:error, message} -> {false, message}
    end
  end

  defp selected_model_id(model_id), do: selected_config(model_id)["model_id"] || default_model_id()

  defp selected_config(model_id) when is_binary(model_id) do
    case Wardwright.model_config(model_id) do
      {:ok, config} -> config
      {:error, _message} -> Wardwright.current_config()
    end
  end

  defp selected_config(_model_id), do: Wardwright.current_config()
end

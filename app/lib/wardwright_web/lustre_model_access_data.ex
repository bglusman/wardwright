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

  def archived_model_options do
    Wardwright.archived_model_summaries()
    |> Enum.map(fn model ->
      {
        model["id"] || "",
        model["description"] || "",
        model["active_version"] || "",
        "archived"
      }
    end)
  end

  def access_summary(model_id) do
    config = selected_config(model_id)
    model = config["model_id"] || model_id || default_model_id()
    requires_api_key = Wardwright.model_requires_api_key?(config)
    unkeyed_access = Wardwright.unkeyed_model_access(config)
    vcr_mode = Wardwright.vcr_mode(config)

    {model, requires_api_key, unkeyed_access, length(Wardwright.ModelApiKeyStore.list(model)), vcr_mode,
     receipt_storage_note()}
  end

  def server_tool_summary(model_id) do
    config = selected_config(model_id)

    {
      config
      |> WardwrightWeb.ModelAccessProjection.server_tool_records()
      |> Enum.map(fn tool ->
        {
          tool["name"] || "",
          tool["engine"] || "",
          tool["source"] || "",
          if(tool["enabled"] == false, do: "disabled", else: "enabled"),
          tool["visibility_level"] || "",
          limit_summary(tool["limits"] || %{}),
          key_summary(tool["parameter_keys"] || []),
          key_summary(tool["input_keys"] || [])
        }
      end),
      config
      |> WardwrightWeb.ModelAccessProjection.server_tool_target_records()
      |> Enum.map(fn target ->
        {
          target["model"] || "",
          target["kind"] || "",
          target_support_label(target["support"] || "")
        }
      end),
      config
      |> WardwrightWeb.ModelAccessProjection.tool_mediation_record()
      |> then(fn mediation ->
        {
          mediation["mode"] || "patch",
          mediation["rule_count"] || 0
        }
      end)
    }
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

  def save_access(model_id, requires_api_key, unkeyed_model_access, vcr_mode) do
    config = selected_config(model_id)

    updated_config =
      config
      |> Map.put("requires_api_key", requires_api_key)
      |> Map.put("auth", %{"unkeyed_model_access" => unkeyed_model_access})
      |> Map.put("vcr", %{"mode" => vcr_mode})

    case Wardwright.put_model_config(updated_config) do
      {:ok, _config} -> {true, save_message(vcr_mode)}
      {:error, message} -> {false, message}
    end
  end

  def archive_model(model_id) do
    model = selected_model_id(model_id)

    case Wardwright.archive_model_config(model) do
      {:ok, archived_model_id} ->
        {true,
         "Archived #{archived_model_id}. It is no longer listed or callable; restore it from Archived models or hard-delete it from SQLite.",
         default_model_id()}

      {:error, message} ->
        {false, message, model}
    end
  end

  def restore_archived_model(model_id) do
    case Wardwright.restore_archived_model_config(model_id) do
      {:ok, config} ->
        restored_model_id = config["model_id"] || model_id
        {true, "Restored #{restored_model_id}. It is active again and available in /v1/models.", restored_model_id}

      {:error, message} ->
        {false, message, default_model_id()}
    end
  end

  def delete_archived_model(model_id) do
    case Wardwright.delete_archived_model_config(model_id) do
      {:ok, deleted_model_id} ->
        {true, "Hard-deleted archived model #{deleted_model_id} from SQLite.", default_model_id()}

      {:error, message} ->
        {false, message, default_model_id()}
    end
  end

  defp save_message("full_session") do
    "Model management settings saved. Full-session request and response payloads will be stored with receipts in #{receipt_storage_note()}."
  end

  defp save_message(_mode) do
    "Model management settings saved. Receipt VCR is metadata-only; receipt metadata is stored in #{receipt_storage_note()}."
  end

  defp receipt_storage_note do
    case Wardwright.ReceiptStore.health() do
      %{"kind" => "file", "path" => path} when is_binary(path) -> "file #{path}"
      %{"kind" => "memory"} -> "memory only; not durable across restart"
      %{"kind" => kind} -> kind
      _health -> "unknown storage"
    end
  end

  defp limit_summary(limits) when is_map(limits) do
    [
      limit_part(limits, "timeout_ms", "timeout", "ms"),
      limit_part(limits, "max_reductions", "reductions", ""),
      limit_part(limits, "max_heap_size", "heap", "")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
    |> case do
      "" -> "default"
      summary -> summary
    end
  end

  defp limit_summary(_limits), do: "default"

  defp limit_part(limits, key, label, suffix) do
    case Map.get(limits, key) do
      value when is_integer(value) -> "#{label} #{value}#{suffix}"
      _value -> nil
    end
  end

  defp key_summary(keys) when is_list(keys) do
    keys
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
    |> case do
      "" -> "none"
      summary -> summary
    end
  end

  defp key_summary(_keys), do: "none"

  defp target_support_label("tool-capable"), do: "Server tools sent to provider"
  defp target_support_label("no-tool-injection"), do: "Server tools not sent"
  defp target_support_label(support), do: support

  defp selected_model_id(model_id), do: selected_config(model_id)["model_id"] || default_model_id()

  defp selected_config(model_id) when is_binary(model_id) do
    case Wardwright.model_config(model_id) do
      {:ok, config} -> config
      {:error, _message} -> Wardwright.current_config()
    end
  end

  defp selected_config(_model_id), do: Wardwright.current_config()
end

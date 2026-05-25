defmodule Wardwright.ToolMediation do
  @moduledoc """
  Normalizes and patches provider-visible Chat Completions tool declarations.

  This is the first narrow slice of the bidirectional tool mediation control
  plane. It intentionally handles request-side tool declarations only; provider
  tool-use event normalization and extension-driven execution are separate
  follow-up surfaces.
  """

  alias Wardwright.AgentAdapters.CanonicalJson

  @additional_properties_key "additionalProperties"
  @action_key "action"
  @applied_rules_key "applied_rules"
  @augment_action "augment"
  @default_mode "patch"
  @declared_by_agent "agent"
  @declared_by_wardwright "wardwright"
  @declared_by_key "declared_by"
  @description_append_key "description_append"
  @description_key "description"
  @enabled_key "enabled"
  @function_key "function"
  @hide_action "hide"
  @id_key "id"
  @match_key "match"
  @mode_key "mode"
  @name_key "name"
  @parameters_key "parameters"
  @matched_tools_key "matched_tools"
  @original_tools_key "original_tools"
  @properties_key "properties"
  @provider_visible_tools_key "provider_visible_tools"
  @replace_action "replace"
  @rules_key "rules"
  @schema "wardwright.tool_mediation.v1"
  @schema_hash_key "schema_hash"
  @schema_key "schema"
  @server_tools_key "server_tools"
  @tool_key "tool"
  @tool_mediation_key "tool_mediation"
  @tool_choice_key "tool_choice"
  @tools_key "tools"
  @type_key "type"
  @function_type "function"

  def apply(%{} = request, %{} = config) do
    rules = mediation_rules(config)

    cond do
      not patch_mode?(config) ->
        {request, nil}

      rules == [] ->
        {request, nil}

      not is_list(Map.get(request, @tools_key)) ->
        {request, nil}

      true ->
        original_tools = Map.get(request, @tools_key, [])
        wardwright_names = configured_server_tool_names(config)
        {patched_tools, applied_rules} = patch_tools(original_tools, rules)

        if applied_rules == [] and patched_tools == original_tools do
          {request, nil}
        else
          request =
            if patched_tools == [] do
              request
              |> Map.drop([@tools_key, @tool_choice_key])
            else
              Map.put(request, @tools_key, patched_tools)
            end

          metadata = %{
            @applied_rules_key => applied_rules,
            @mode_key => mediation_mode(config),
            @original_tools_key => Enum.map(original_tools, &tool_descriptor(&1, wardwright_names)),
            @provider_visible_tools_key => Enum.map(patched_tools, &tool_descriptor(&1, wardwright_names)),
            @schema_key => @schema
          }

          {request, metadata}
        end
    end
  end

  def apply(request, _config), do: {request, nil}

  defp patch_tools(tools, rules) do
    Enum.reduce(rules, {tools, []}, fn rule, {current_tools, applied_rules} ->
      apply_rule(current_tools, rule, applied_rules)
    end)
    |> then(fn {patched_tools, applied_rules} -> {patched_tools, Enum.reverse(applied_rules)} end)
  end

  defp apply_rule(tools, %{@enabled_key => false}, applied_rules), do: {tools, applied_rules}

  defp apply_rule(tools, rule, applied_rules) when is_map(rule) do
    action = rule |> Map.get(@action_key, "") |> to_string()
    {patched, matched_names} = patch_matching_tools(tools, rule, action)

    if matched_names == [] or not supported_action?(action) do
      {tools, applied_rules}
    else
      {deduplicate_tool_names(patched),
       [
         %{
           @action_key => action,
           @id_key => rule_id(rule),
           @matched_tools_key => matched_names
         }
         | applied_rules
       ]}
    end
  end

  defp apply_rule(tools, _rule, applied_rules), do: {tools, applied_rules}

  defp patch_matching_tools(tools, rule, action) do
    Enum.reduce(tools, {[], []}, fn tool, {kept, matched_names} ->
      if rule_matches_tool?(rule, tool) do
        name = tool_name(tool)

        case patch_tool(tool, rule, action) do
          :hide -> {kept, prepend_present(matched_names, name)}
          {:replace, replacement} -> {[replacement | kept], prepend_present(matched_names, name)}
          {:keep, patched_tool} -> {[patched_tool | kept], prepend_present(matched_names, name)}
          {:unchanged, original_tool} -> {[original_tool | kept], matched_names}
        end
      else
        {[tool | kept], matched_names}
      end
    end)
    |> then(fn {kept, matched_names} -> {Enum.reverse(kept), Enum.reverse(matched_names)} end)
  end

  defp patch_tool(_tool, _rule, @hide_action), do: :hide

  defp patch_tool(tool, rule, @augment_action) do
    patched_tool =
      tool
      |> append_description(Map.get(rule, @description_append_key))
      |> replace_parameters(Map.get(rule, @parameters_key))

    if patched_tool == tool, do: {:unchanged, tool}, else: {:keep, patched_tool}
  end

  defp patch_tool(tool, %{@tool_key => replacement}, @replace_action) when is_map(replacement) do
    replacement = normalize_tool_schema(replacement)
    if replacement == tool, do: {:unchanged, tool}, else: {:replace, replacement}
  end

  defp patch_tool(tool, _rule, _action), do: {:unchanged, tool}

  defp supported_action?(action) when action in [@hide_action, @augment_action, @replace_action], do: true

  defp supported_action?(_action), do: false

  defp append_description(tool, suffix) when is_binary(suffix) and suffix != "" do
    update_function(tool, fn function ->
      existing = function |> Map.get(@description_key, "") |> to_string()
      description = [existing, suffix] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
      Map.put(function, @description_key, description)
    end)
  end

  defp append_description(tool, _suffix), do: tool

  defp replace_parameters(tool, parameters) when is_map(parameters) do
    update_function(tool, &Map.put(&1, @parameters_key, parameters))
  end

  defp replace_parameters(tool, _parameters), do: tool

  defp update_function(%{@function_key => function} = tool, fun) when is_map(function),
    do: Map.put(tool, @function_key, fun.(function))

  defp update_function(tool, _fun), do: tool

  defp rule_matches_tool?(%{@match_key => match}, tool) when is_map(match), do: matcher_matches_tool?(match, tool)
  defp rule_matches_tool?(rule, tool), do: matcher_matches_tool?(rule, tool)

  defp matcher_matches_tool?(%{@name_key => name}, tool) when is_binary(name), do: tool_name(tool) == name
  defp matcher_matches_tool?(_match, _tool), do: false

  defp tool_descriptor(tool, wardwright_names) do
    name = tool_name(tool)

    %{
      @declared_by_key => if(name in wardwright_names, do: @declared_by_wardwright, else: @declared_by_agent),
      @name_key => name,
      @schema_hash_key => schema_hash(tool),
      @type_key => tool_type(tool)
    }
  end

  defp normalize_tool_schema(%{@function_key => %{} = _function} = tool),
    do: Map.put_new(tool, @type_key, @function_type)

  defp normalize_tool_schema(%{@name_key => name} = tool) do
    %{
      @function_key => %{
        @description_key => Map.get(tool, @description_key, ""),
        @name_key => name,
        @parameters_key => Map.get(tool, @parameters_key, default_parameters())
      },
      @type_key => @function_type
    }
  end

  defp normalize_tool_schema(tool), do: tool

  defp tool_name(%{@function_key => %{@name_key => name}}) when is_binary(name), do: name
  defp tool_name(%{@name_key => name}) when is_binary(name), do: name
  defp tool_name(_tool), do: nil

  defp tool_type(%{@type_key => type}) when is_binary(type), do: type
  defp tool_type(_tool), do: @function_type

  defp schema_hash(tool),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, CanonicalJson.encode!(tool)), case: :lower)

  defp deduplicate_tool_names(tools) do
    tools
    |> Enum.reverse()
    |> Enum.reduce({[], MapSet.new()}, fn tool, {kept, seen} ->
      case tool_name(tool) do
        nil ->
          {[tool | kept], seen}

        name ->
          if MapSet.member?(seen, name) do
            {kept, seen}
          else
            {[tool | kept], MapSet.put(seen, name)}
          end
      end
    end)
    |> elem(0)
  end

  defp mediation_rules(config) do
    config
    |> Map.get(@tool_mediation_key, %{})
    |> case do
      %{@rules_key => rules} when is_list(rules) -> rules
      rules when is_list(rules) -> rules
      _other -> []
    end
    |> Enum.filter(&is_map/1)
  end

  defp mediation_mode(config) do
    config
    |> Map.get(@tool_mediation_key, %{})
    |> case do
      %{@mode_key => mode} when is_binary(mode) and mode != "" -> mode
      _other -> @default_mode
    end
  end

  defp patch_mode?(config), do: mediation_mode(config) == @default_mode

  defp configured_server_tool_names(config) do
    config
    |> Map.get(@server_tools_key, [])
    |> List.wrap()
    |> Enum.flat_map(fn
      %{@name_key => name} when is_binary(name) and name != "" -> [name]
      name when is_binary(name) and name != "" -> [name]
      _tool -> []
    end)
  end

  defp prepend_present(list, nil), do: list
  defp prepend_present(list, value), do: [value | list]

  defp rule_id(%{@id_key => id}) when is_binary(id) and id != "", do: id
  defp rule_id(_rule), do: "tool-mediation"

  defp default_parameters do
    %{
      @additional_properties_key => true,
      @properties_key => %{},
      @type_key => "object"
    }
  end
end

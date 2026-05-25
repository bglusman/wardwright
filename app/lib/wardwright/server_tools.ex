defmodule Wardwright.ServerTools do
  @moduledoc false

  alias Wardwright.PolicySandbox.Dune
  alias Wardwright.PolicySandbox.DuneSnippetRegistry

  @additional_properties_key "additionalProperties"
  @arguments_key "arguments"
  @beam_module_engine "beam_module"
  @builtin_engine "builtin"
  @call_id_key "call_id"
  @completed_status "completed"
  @config_key "config"
  @content_key "content"
  @description_key "description"
  @dune_default_description "Run a trusted local Wardwright Dune server function."
  @dune_engine "dune"
  @enabled_key "enabled"
  @engine_key "engine"
  @entry_count_key "entry_count"
  @error_key "error"
  @elixir_module_engine "elixir_module"
  @execution_location_key "execution_location"
  @finish_reason_key "finish_reason"
  @function_key "function"
  @function_type "function"
  @id_key "id"
  @input_key "input"
  @kind_key "kind"
  @limits_key "limits"
  @local_verified_visibility "local_verified"
  @max_heap_size_key "max_heap_size"
  @max_reductions_key "max_reductions"
  @message_key "message"
  @messages_key "messages"
  @module_key "module"
  @name_key "name"
  @object_type "object"
  @parameters_key "parameters"
  @path_key "path"
  @policy_cache_status "wardwright_policy_cache_status"
  @properties_key "properties"
  @provider_metadata_server_tool_finish_reason_key "wardwright_server_tool_first_finish_reason"
  @provider_metadata_server_tools_key "wardwright_server_tools"
  @request_key "request"
  @result_metadata_key "result_metadata"
  @role_key "role"
  @server_tools_key "server_tools"
  @session_count_key "session_count"
  @source_key "source"
  @snippet_id_key "snippet_id"
  @status_key "status"
  @stream_key "stream"
  @timeout_ms_key "timeout_ms"
  @tool_call_id_key "tool_call_id"
  @tool_calls_key "tool_calls"
  @tool_choice_key "tool_choice"
  @tool_mediation_key "wardwright_tool_mediation"
  @tool_role "tool"
  @tools_key "tools"
  @topology_key "topology"
  @type_key "type"
  @unsupported_status "unsupported"
  @value_key "value"
  @visibility_level_key "visibility_level"
  @wardwright_execution_location "wardwright"

  def registered_tool_names, do: Enum.map(builtin_tools(), & &1.name)

  def complete_selected_model(selected_model, request, config) when is_map(request) and is_map(config) do
    tools = configured_tools(config)

    cond do
      Map.get(request, @stream_key) == true ->
        Wardwright.complete_selected_model(selected_model, request, config)

      tools == [] ->
        {request, mediation} = Wardwright.ToolMediation.apply(request, config)

        selected_model
        |> Wardwright.complete_selected_model(request, config)
        |> add_tool_mediation_metadata(mediation)

      true ->
        {request, mediation} =
          request
          |> inject_tools(tools)
          |> Wardwright.ToolMediation.apply(config)

        request
        |> complete_with_tool_loop(selected_model, config, tools)
        |> add_tool_mediation_metadata(mediation)
    end
  end

  defp complete_with_tool_loop(request, selected_model, config, tools) do
    first = Wardwright.complete_selected_model(selected_model, request, config)

    with %{response_message: %{} = message} <- first,
         {:ok, tool_call, tool} <- requested_server_tool(message, tools),
         {:ok, tool_message, execution} <- execute_tool(tool_call, tool, request, config) do
      followup =
        request
        |> Map.update(@messages_key, [message, tool_message], &(&1 ++ [message, tool_message]))

      selected_model
      |> Wardwright.complete_selected_model(followup, config)
      |> add_server_tool_metadata(first, execution)
    else
      _no_server_tool -> first
    end
  end

  defp requested_server_tool(message, tools) do
    message
    |> Map.get(@tool_calls_key, [])
    |> Enum.find_value(fn
      %{@function_key => %{@name_key => name}} = call ->
        tool = Enum.find(tools, &(Map.get(&1, @name_key) == name))
        if tool, do: {:ok, call, tool}

      _call ->
        nil
    end)
    |> case do
      nil -> :error
      result -> result
    end
  end

  defp execute_tool(%{@function_key => %{@name_key => name} = function, @id_key => call_id}, tool, request, config) do
    arguments = parse_arguments(Map.get(function, @arguments_key))
    tool = Map.put_new(tool, @name_key, name)

    case run_tool(tool, arguments, request, config) do
      {:ok, result} ->
        tool_message = %{
          @content_key => JSON.encode!(result),
          @role_key => @tool_role,
          @tool_call_id_key => call_id
        }

        execution =
          tool
          |> execution_record(call_id, @completed_status)
          |> Map.put(@result_metadata_key, result)

        {:ok, tool_message, execution}

      {:error, reason} ->
        error = inspect(reason)

        tool_message = %{
          @content_key => JSON.encode!(%{@error_key => error}),
          @role_key => @tool_role,
          @tool_call_id_key => call_id
        }

        execution =
          tool
          |> execution_record(call_id, @unsupported_status)
          |> Map.put(@error_key, error)

        {:ok, tool_message, execution}
    end
  end

  defp execute_tool(_call, _tool, _request, _config), do: :error

  defp parse_arguments(arguments) when is_map(arguments), do: arguments

  defp parse_arguments(arguments) when is_binary(arguments) do
    case JSON.decode(arguments) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _error -> %{}
    end
  end

  defp parse_arguments(_arguments), do: %{}

  defp add_server_tool_metadata(second, first, execution) do
    provider_metadata =
      second
      |> Map.get(:provider_metadata, %{})
      |> Kernel.||(%{})
      |> Map.put(@provider_metadata_server_tools_key, [execution])
      |> Map.put(
        @provider_metadata_server_tool_finish_reason_key,
        get_in(first, [:provider_metadata, @finish_reason_key])
      )

    latency_ms = Map.get(first, :latency_ms, 0) + Map.get(second, :latency_ms, 0)

    second
    |> Map.put(:provider_metadata, provider_metadata)
    |> Map.put(:latency_ms, latency_ms)
  end

  defp add_tool_mediation_metadata(outcome, nil), do: outcome

  defp add_tool_mediation_metadata(outcome, mediation) when is_map(mediation) do
    provider_metadata =
      outcome
      |> Map.get(:provider_metadata, %{})
      |> Kernel.||(%{})
      |> Map.put(@tool_mediation_key, mediation)

    Map.put(outcome, :provider_metadata, provider_metadata)
  end

  defp execution_record(tool, call_id, status) do
    %{
      @call_id_key => call_id,
      @engine_key => Map.get(tool, @engine_key, @builtin_engine),
      @execution_location_key => @wardwright_execution_location,
      @name_key => Map.get(tool, @name_key),
      @status_key => status,
      @visibility_level_key => @local_verified_visibility
    }
  end

  defp inject_tools(request, tools) do
    registered_schemas = Enum.flat_map(tools, &tool_schema/1)

    request
    |> Map.update(@tools_key, registered_schemas, fn existing ->
      existing = if is_list(existing), do: existing, else: []
      existing_names = Enum.map(existing, &tool_schema_name/1)
      existing ++ Enum.reject(registered_schemas, &(tool_schema_name(&1) in existing_names))
    end)
    |> Map.put_new(@tool_choice_key, "auto")
  end

  defp tool_schema(tool) do
    case tool_spec(tool) do
      {:ok, spec} ->
        [
          %{
            @function_key => %{
              @description_key => Map.get(spec, @description_key, ""),
              @name_key => Map.fetch!(spec, @name_key),
              @parameters_key => Map.get(spec, @parameters_key, default_parameters())
            },
            @type_key => @function_type
          }
        ]

      {:error, _reason} ->
        []
    end
  end

  defp tool_schema_name(%{@function_key => %{@name_key => name}}), do: name
  defp tool_schema_name(_schema), do: nil

  defp configured_tools(config) do
    config
    |> Map.get(@server_tools_key, [])
    |> List.wrap()
    |> Enum.flat_map(&normalize_tool/1)
  end

  defp normalize_tool(%{@enabled_key => false}), do: []

  defp normalize_tool(%{} = tool) do
    tool = normalize_engine(tool)

    case Map.get(tool, @engine_key, @builtin_engine) do
      @builtin_engine ->
        case builtin_tool(Map.get(tool, @name_key)) do
          nil -> []
          builtin -> [%{@engine_key => @builtin_engine, @name_key => builtin.name}]
        end

      @dune_engine ->
        if present?(Map.get(tool, @name_key)) and
             (present?(Map.get(tool, @source_key)) or present?(Map.get(tool, @snippet_id_key))) do
          [tool]
        else
          []
        end

      @beam_module_engine ->
        if present?(Map.get(tool, @module_key)) or present?(Map.get(tool, @path_key)) do
          case tool_spec(tool) do
            {:ok, spec} -> [Map.put(tool, @name_key, Map.fetch!(spec, @name_key))]
            {:error, _reason} -> []
          end
        else
          []
        end

      _unknown ->
        []
    end
  end

  defp normalize_tool(name) when is_binary(name) do
    case builtin_tool(name) do
      nil -> []
      tool -> [%{@engine_key => @builtin_engine, @name_key => tool.name}]
    end
  end

  defp normalize_tool(_tool), do: []

  defp normalize_engine(tool) do
    case Map.get(tool, @engine_key) do
      @elixir_module_engine -> Map.put(tool, @engine_key, @beam_module_engine)
      nil -> Map.put(tool, @engine_key, default_engine(tool))
      _engine -> tool
    end
  end

  defp default_engine(tool) do
    cond do
      present?(Map.get(tool, @source_key)) or present?(Map.get(tool, @snippet_id_key)) -> @dune_engine
      present?(Map.get(tool, @module_key)) or present?(Map.get(tool, @path_key)) -> @beam_module_engine
      true -> @builtin_engine
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp tool_spec(%{@engine_key => @builtin_engine, @name_key => name}) do
    case builtin_tool(name) do
      nil -> {:error, :unknown_builtin_tool}
      tool -> {:ok, builtin_tool_spec(tool)}
    end
  end

  defp tool_spec(%{@engine_key => @dune_engine} = tool) do
    {:ok,
     %{
       @description_key => Map.get(tool, @description_key, @dune_default_description),
       @name_key => Map.fetch!(tool, @name_key),
       @parameters_key => Map.get(tool, @parameters_key, default_parameters())
     }}
  end

  defp tool_spec(%{@engine_key => @beam_module_engine} = tool) do
    case load_tool_module(tool) do
      {:ok, module} ->
        with true <- function_exported?(module, :spec, 0) || {:error, :missing_spec_callback},
             true <- function_exported?(module, :run, 2) || {:error, :missing_run_callback},
             spec when is_map(spec) <- module.spec() do
          {:ok, spec}
        else
          {:error, reason} -> configured_tool_spec(tool, reason)
          _invalid -> configured_tool_spec(tool, :invalid_module_spec)
        end

      {:error, reason} ->
        configured_tool_spec(tool, reason)
    end
  end

  defp tool_spec(tool), do: tool_spec(normalize_engine(tool))

  defp configured_tool_spec(%{@name_key => name} = tool, _fallback_reason) when is_binary(name) and name != "" do
    {:ok,
     %{
       @description_key => Map.get(tool, @description_key, ""),
       @name_key => name,
       @parameters_key => Map.get(tool, @parameters_key, default_parameters())
     }}
  end

  defp configured_tool_spec(_tool, reason), do: {:error, reason}

  defp builtin_tool_spec(tool) do
    %{
      @description_key => tool.description,
      @name_key => tool.name,
      @parameters_key => tool.parameters
    }
  end

  defp builtin_tool(name), do: Enum.find(builtin_tools(), &(&1.name == name))

  defp builtin_tools do
    [
      %{
        description: "Read Wardwright's bounded policy-cache status for the current service.",
        name: @policy_cache_status,
        parameters: %{
          @additional_properties_key => false,
          @properties_key => %{},
          @type_key => @object_type
        },
        run: &policy_cache_status_result/0
      }
    ]
  end

  defp run_tool(%{@engine_key => @builtin_engine, @name_key => name}, _arguments, _request, _config) do
    case builtin_tool(name) do
      %{run: run} -> {:ok, run.()}
      _unknown -> {:error, :unsupported_builtin_tool}
    end
  end

  defp run_tool(%{@engine_key => @dune_engine} = tool, arguments, _request, _config) do
    with {:ok, source} <- dune_source(tool) do
      input =
        tool
        |> Map.get(@input_key, %{})
        |> case do
          defaults when is_map(defaults) -> Map.merge(defaults, arguments)
          _defaults -> arguments
        end

      case Dune.eval_snippet(source, input, dune_opts(Map.get(tool, @limits_key, %{}))) do
        %{@status_key => "ok", @value_key => value} when is_map(value) -> {:ok, value}
        %{@status_key => "ok", @value_key => value} -> {:ok, %{@value_key => value}}
        %{@message_key => message} -> {:error, message}
        result -> {:error, result}
      end
    end
  end

  defp run_tool(%{@engine_key => @beam_module_engine} = tool, arguments, request, config) do
    with {:ok, module} <- load_tool_module(tool),
         true <- function_exported?(module, :run, 2) || {:error, :missing_run_callback} do
      case module.run(arguments, %{@config_key => config, @request_key => request}) do
        {:ok, result} when is_map(result) -> {:ok, result}
        {:error, reason} -> {:error, reason}
        result when is_map(result) -> {:ok, result}
        result -> {:ok, %{@value_key => result}}
      end
    end
  end

  defp run_tool(_tool, _arguments, _request, _config), do: {:error, :unsupported_server_tool_engine}

  defp dune_source(%{@source_key => source}) when is_binary(source) and source != "", do: {:ok, source}

  defp dune_source(%{@snippet_id_key => snippet_id}) when is_binary(snippet_id) and snippet_id != "" do
    case DuneSnippetRegistry.get(snippet_id) do
      {:ok, snippet} -> {:ok, Map.fetch!(snippet, @source_key)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dune_source(_tool), do: {:error, :missing_dune_source}

  defp dune_opts(limits) when is_map(limits) do
    []
    |> put_positive_opt(:timeout, Map.get(limits, @timeout_ms_key))
    |> put_positive_opt(:max_reductions, Map.get(limits, @max_reductions_key))
    |> put_positive_opt(:max_heap_size, Map.get(limits, @max_heap_size_key))
  end

  defp dune_opts(_limits), do: []

  defp put_positive_opt(opts, key, value) when is_integer(value) and value > 0, do: Keyword.put(opts, key, value)
  defp put_positive_opt(opts, _key, _value), do: opts

  defp load_tool_module(tool) do
    with {:ok, loaded_modules} <- load_tool_path(Map.get(tool, @path_key)) do
      select_tool_module(Map.get(tool, @module_key), loaded_modules)
    end
  end

  defp load_tool_path(path) when is_binary(path) and path != "" do
    path = Path.expand(path)
    extension = Path.extname(path)

    cond do
      extension in [".ex", ".exs"] ->
        case Code.require_file(path) do
          modules when is_list(modules) -> {:ok, Enum.map(modules, &elem(&1, 0))}
          nil -> {:ok, []}
        end

      extension == ".erl" ->
        compile_erlang_tool(path)

      extension == ".beam" ->
        load_beam_tool(path)

      true ->
        {:error, :unsupported_beam_tool_path}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp load_tool_path(_path), do: {:ok, []}

  defp compile_erlang_tool(path) do
    path_chars = String.to_charlist(path)

    case apply(:compile, :file, [path_chars, [:binary, :return_errors, :return_warnings]]) do
      {:ok, module, binary} ->
        :code.load_binary(module, path_chars, binary)
        {:ok, [module]}

      {:ok, module, binary, _warnings} ->
        :code.load_binary(module, path_chars, binary)
        {:ok, [module]}

      {:error, errors, _warnings} ->
        {:error, {:erlang_compile_failed, errors}}
    end
  end

  defp load_beam_tool(path) do
    with {:ok, module} <- beam_module(path),
         {:ok, binary} <- File.read(path),
         {:module, ^module} <- :code.load_binary(module, String.to_charlist(path), binary) do
      {:ok, [module]}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:beam_load_failed, other}}
    end
  end

  defp beam_module(path) do
    path
    |> String.to_charlist()
    |> :beam_lib.info()
    |> Enum.find_value(fn
      {:module, module} -> {:ok, module}
      _info -> nil
    end)
    |> case do
      nil -> {:error, :unknown_beam_module}
      result -> result
    end
  end

  defp select_tool_module(nil, [module]), do: {:ok, module}

  defp select_tool_module(module_name, loaded_modules) when is_binary(module_name) do
    candidates = module_name_candidates(module_name)

    Enum.find_value(candidates, fn candidate ->
      cond do
        candidate in loaded_modules -> {:ok, candidate}
        function_exported?(candidate, :run, 2) -> {:ok, candidate}
        Code.ensure_loaded?(candidate) and function_exported?(candidate, :run, 2) -> {:ok, candidate}
        true -> nil
      end
    end) || {:error, :module_not_loaded}
  end

  defp select_tool_module(module, _loaded_modules) when is_atom(module) do
    if Code.ensure_loaded?(module), do: {:ok, module}, else: {:error, :module_not_loaded}
  end

  defp select_tool_module(_module_name, _loaded_modules), do: {:error, :module_not_loaded}

  defp module_name_candidates(module_name) do
    module_name = String.trim(module_name)

    [
      existing_atom(module_name),
      if(!String.starts_with?(module_name, "Elixir."), do: existing_atom("Elixir." <> module_name))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp existing_atom(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> nil
  end

  defp default_parameters do
    %{
      @additional_properties_key => true,
      @properties_key => %{},
      @type_key => @object_type
    }
  end

  defp policy_cache_status_result do
    status = Wardwright.PolicyCache.status()

    %{
      @entry_count_key => status[@entry_count_key],
      @kind_key => status[@kind_key],
      @session_count_key => status[@session_count_key],
      @topology_key => status[@topology_key]
    }
  end
end

defmodule Wardwright.CLI do
  @moduledoc false

  def run(argv, write_fun \\ &IO.puts/1) do
    case argv do
      ["--version" | _] ->
        write_fun.(version())
        {:halt, 0}

      ["version" | _] ->
        write_fun.(version())
        {:halt, 0}

      ["--help" | _] ->
        write_fun.(help())
        {:halt, 0}

      ["help" | _] ->
        write_fun.(help())
        {:halt, 0}

      ["serve" | _] ->
        :start

      ["start" | _] ->
        :start

      ["tools", "--json" | _] ->
        WardwrightWeb.PolicyAuthoringTools.list()
        |> Jason.encode!()
        |> write_fun.()

        {:halt, 0}

      ["tools" | _] ->
        write_fun.(tools_help())
        {:halt, 0}

      [] ->
        write_fun.(help())
        {:halt, 0}

      _unknown ->
        write_fun.(help())
        {:halt, 2}
    end
  end

  defp help do
    """
    wardwright #{version()}

    Usage:
      wardwright                Print this help
      wardwright serve          Start the Wardwright HTTP service
      wardwright tools          Print policy-authoring MCP/API help for agents
      wardwright tools --json   Print machine-readable authoring tool metadata
      wardwright --version      Print the packaged app version

    Runtime environment:
      WARDWRIGHT_BIND             Host and port, default 127.0.0.1:8787
      WARDWRIGHT_ALLOWED_ORIGINS  Extra comma-separated LiveView origins
      WARDWRIGHT_SECRET_KEY_BASE  Stable Phoenix signing secret for services
      WARDWRIGHT_ADMIN_TOKEN      Optional token for protected local APIs
      BASIC_AUTH_PASSWORD         Optional password for protected operator UI/APIs; user is admin
      WARDWRIGHT_MODEL_API_KEY_STORE  Optional path for hashed model API keys
      WARDWRIGHT_MODEL_API_KEY_HASH_SECRET  Optional stable secret for model API key hashes
    """
  end

  defp tools_help do
    tools = WardwrightWeb.PolicyAuthoringTools.cli_descriptions() |> Enum.join("\n")

    """
    Wardwright policy-authoring tools

    Start Wardwright, then point MCP-capable agents at:
      http://127.0.0.1:8787/mcp

    Local HTTP tools are protected by loopback access or WARDWRIGHT_ADMIN_TOKEN.
    When Wardwright is bound to another port, replace 8787 with WARDWRIGHT_BIND.
    Agent guide: https://wardwright.dev/agent-authoring.html

    Tools:
    #{tools}
    """
  end

  defp version do
    :wardwright
    |> Application.spec(:vsn)
    |> to_string()
  end
end

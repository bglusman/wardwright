defmodule Wardwright.CLI do
  @moduledoc false

  alias Wardwright.CLI.Adapters
  alias Wardwright.CLI.Admin

  def run(argv, write_fun \\ &IO.puts/1, admin_fun \\ &Admin.open/2, adapters_fun \\ &Adapters.run/2) do
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

      ["admin" | rest] ->
        status = admin_fun.(admin_path(rest), write_fun)
        {:halt, status}

      ["adapters" | rest] ->
        status = adapters_fun.(rest, write_fun)
        {:halt, status}

      ["tools", "--json" | _] ->
        WardwrightWeb.PolicyAuthoringTools.list()
        |> JSON.encode!()
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
      wardwright admin          Open the operator workbench, starting it if needed
      wardwright admin access   Open Model Management
      wardwright adapters list     List installable agent adapter targets
      wardwright adapters doctor   Detect local adapter/runtime status
      wardwright adapters install  Install project-local adapter files
      wardwright adapters uninstall  Remove Wardwright-owned adapter files
      wardwright adapters pair     Pair installed adapter files with the gateway
      wardwright tools          Print policy-authoring MCP/API help for agents
      wardwright tools --json   Print machine-readable authoring tool metadata
      wardwright --version      Print the packaged app version

    Runtime environment:
      WARDWRIGHT_BIND             Host and port, default 127.0.0.1:8787
      WARDWRIGHT_ALLOWED_ORIGINS  Extra comma-separated LiveView origins
      WARDWRIGHT_SECRET_KEY_BASE  Stable Phoenix signing secret for services
      WARDWRIGHT_ADMIN_TOKEN      Optional token for protected local APIs
      BASIC_AUTH_PASSWORD         Optional password for protected operator UI/APIs; user is admin
      WARDWRIGHT_SQLITE_STORE     Optional SQLite path for models and hashed API keys
      WARDWRIGHT_RECEIPT_STORE_DIR  Optional directory for per-receipt JSON files
      WARDWRIGHT_TRANSCRIPT_STORE_DIR  Optional directory for replayable session trace events
      WARDWRIGHT_POLICY_SCENARIO_STORE_FILE  Optional JSON file for durable simulator cases
      WARDWRIGHT_SQLITE_KEY       Optional SQLCipher key for the SQLite store
      WARDWRIGHT_SQLITE_KEY_FNOX  Optional fnox secret name for the SQLite SQLCipher key
      WARDWRIGHT_MODEL_API_KEY_HASH_SECRET  Optional stable secret for model API key hashes
    """
  end

  defp admin_path(["access" | _]), do: "/admin?view=model_access"
  defp admin_path(["keys" | _]), do: "/admin?view=model_access"
  defp admin_path(_rest), do: "/admin"

  defp tools_help do
    tools = WardwrightWeb.PolicyAuthoringTools.cli_descriptions() |> Enum.join("\n")

    """
    Wardwright policy-authoring tools

    Start Wardwright, then point MCP-capable agents at:
      http://127.0.0.1:8787/mcp

    Local HTTP tools are protected by loopback access or WARDWRIGHT_ADMIN_TOKEN.
    When Wardwright is bound to another port, replace 8787 with WARDWRIGHT_BIND.
    This command is the cold-start help surface for agents: it should provide
    enough context to discover the UI, MCP, and HTTP authoring/debugging paths
    without reading the repository first.
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

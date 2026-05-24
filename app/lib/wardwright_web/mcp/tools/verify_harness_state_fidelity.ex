defmodule WardwrightWeb.MCP.Tools.VerifyHarnessStateFidelity do
  @moduledoc """
  Compare an exported harness state-fidelity probe with observed imported state.

  This verifies the concrete probe evidence only. It does not by itself prove
  native equivalent agent resume.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.AgentHarnessAdapters
  alias WardwrightWeb.MCP.Tools

  schema do
    field(:probe, :map, required: true, description: "state_fidelity_probe object from an exported harness trace.")

    field(:observed, :map,
      required: true,
      description:
        "Observed imported-harness state: trace_fingerprint, tool_result_fingerprints or events, and read_before_edit_cursor_identified."
    )
  end

  @impl true
  def execute(params, frame) do
    probe = Map.get(params, :probe) || Map.get(params, "probe")
    observed = Map.get(params, :observed) || Map.get(params, "observed")

    case AgentHarnessAdapters.verify_state_fidelity(probe, observed) do
      {:error, message} -> Tools.execution_error(message, frame)
      verification -> Tools.reply_json(%{"verification" => verification}, frame)
    end
  end
end

defmodule Wardwright.AgentAdapters.OmpPack do
  @moduledoc false

  alias Wardwright.AgentAdapters.CanonicalJson

  @adapter_id "wardwright-omp"
  @adapter_version "0.1.0-rc.1"
  @config_path ".omp/wardwright-adapter.json"
  @default_gateway_url "http://127.0.0.1:8787"
  @key_gateway_url "gateway_url"
  @manifest_path ".omp/wardwright-adapter-manifest.json"

  def adapter_id, do: @adapter_id
  def adapter_version, do: @adapter_version
  def config_path, do: @config_path
  def manifest_path, do: @manifest_path
  def runtime, do: "omp"
  def target, do: "omp"

  def expected_files do
    files = content_files()

    files ++
      [
        %{
          content: manifest_content(files),
          path: @manifest_path
        }
      ]
  end

  def content_files do
    [
      %{
        content: rule_content(),
        path: ".omp/rules/wardwright-read-before-edit.md"
      },
      %{
        content: state_fidelity_extension_content(),
        path: ".omp/extensions/wardwright-state-fidelity.ts"
      },
      %{
        content: adapter_config_content(),
        dynamic?: true,
        path: @config_path
      }
    ]
  end

  def rule_content do
    """
    ---
    description: Wardwright read-before-edit replay guard
    condition:
      - "."
    scope:
      - "tool:edit(*)"
      - "tool:write(*)"
      - "tool:patch(*)"
      - "tool:edit_file(*)"
      - "tool:write_file(*)"
    interruptMode: "always"
    ---

    If a continuation is about to edit or write a file from an imported
    Wardwright trace, require explicit read evidence for the same path first.
    Treat missing read evidence as a replay finding, not as permission to keep
    editing.
    """
  end

  def state_fidelity_extension_content do
    """
    import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
    import { createHash } from "node:crypto";
    import { readFileSync } from "node:fs";

    function digest(value: unknown): string {
      return createHash("sha256").update(JSON.stringify(value)).digest("hex");
    }

    export default function wardwrightStateFidelity(pi: ExtensionAPI) {
      const z = pi.zod;

      pi.registerTool({
        name: "wardwright_verify_state_fidelity",
        label: "Verify Wardwright fidelity",
        description: "Compare an exported Wardwright probe with observed Pi replay state.",
        parameters: z.object({
          probePath: z.string(),
          observed: z.any(),
        }),
        async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
          try {
            const probe = JSON.parse(readFileSync(params.probePath, "utf8"));
            const observed = params.observed ?? {};
            return {
              content: [{ type: "text", text: JSON.stringify({
                schema: "wardwright.pi_state_fidelity_verification_spike.v0",
                adapter_id: probe.adapter_id,
                trace_fingerprint_matches: probe.trace_fingerprint === observed.trace_fingerprint,
                observed_digest: digest(observed),
                equivalent_agent_resume_claim_allowed: false,
              }) }],
              details: {},
            };
          } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            return {
              content: [{ type: "text", text: `Error verifying Wardwright fidelity: ${message}` }],
              details: { error: message },
            };
          }
        },
      });
    }
    """
  end

  def adapter_config_content(identity \\ nil, runtime_probe \\ nil) do
    %{
      adapter_id: @adapter_id,
      adapter_version: @adapter_version,
      gateway_identity: identity,
      gateway_url: gateway_url(identity),
      paired: is_map(identity),
      runtime: "omp",
      runtime_probe: runtime_probe,
      schema: "wardwright.adapter_config.v0",
      target: "omp"
    }
    |> CanonicalJson.encode!()
    |> Kernel.<>("\n")
  end

  defp manifest_content(files) do
    %{
      adapter_id: @adapter_id,
      adapter_version: @adapter_version,
      files: Enum.map(files, &manifest_entry/1),
      runtime: "omp",
      schema: "wardwright.adapter_manifest.v0",
      target: "omp"
    }
    |> CanonicalJson.encode!()
    |> Kernel.<>("\n")
  end

  defp manifest_entry(%{dynamic?: true} = file) do
    %{
      dynamic: true,
      path: file.path,
      validator: "adapter_config_schema"
    }
  end

  defp manifest_entry(file) do
    %{
      path: file.path,
      sha256: sha256(file.content)
    }
  end

  defp gateway_url(identity) when is_map(identity), do: Map.get(identity, @key_gateway_url, @default_gateway_url)
  defp gateway_url(_identity), do: @default_gateway_url

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end

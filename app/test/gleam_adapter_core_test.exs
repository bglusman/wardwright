defmodule Wardwright.GleamAdapterCoreTest do
  use ExUnit.Case, async: true

  test "adapter state classification preserves verification and drift precedence" do
    assert :wardwright@adapter_core.contract_version() == "wardwright.adapter_install.v0"

    assert :wardwright@adapter_core.adapter_state(false, true, true, false, true, false, false) ==
             "not_detected"

    assert :wardwright@adapter_core.adapter_state(true, false, true, false, true, false, false) ==
             "unsupported_runtime"

    assert :wardwright@adapter_core.adapter_state(true, true, true, false, true, false, false) ==
             "installable"

    assert :wardwright@adapter_core.adapter_state(true, true, true, true, true, false, false) ==
             "installed_unverified"

    assert :wardwright@adapter_core.adapter_state(true, true, true, true, false, true, true) ==
             "drifted"

    assert :wardwright@adapter_core.adapter_state(true, true, true, true, true, true, false) ==
             "verified"

    assert :wardwright@adapter_core.adapter_state(true, true, true, true, true, true, true) ==
             "verified_with_probe"
  end

  test "runtime resolution distinguishes native adapters, inherited coverage, and lower-fidelity fallbacks" do
    assert :wardwright@adapter_core.resolve_adapter("omp", "omp") ==
             {"wardwright-omp", "native_runtime", "install_runtime_adapter", "tts_runtime_probe"}

    assert :wardwright@adapter_core.resolve_adapter("opencode", "omp") ==
             {"wardwright-omp", "covered_through_runtime", "install_runtime_adapter", "runtime_verified"}

    assert :wardwright@adapter_core.resolve_adapter("opencode", "opencode-native") ==
             {"wardwright-opencode", "surface_scaffold", "no_install", "session_import_best_effort"}

    assert :wardwright@adapter_core.resolve_adapter("opencode", "codex") ==
             {"wardwright-codex", "gateway_identity", "install_gateway_identity", "prompt_handoff"}

    assert :wardwright@adapter_core.resolve_adapter("openclaw", "auto-pi") ==
             {"wardwright-pi", "covered_through_runtime", "install_runtime_adapter", "runtime_verified"}

    assert :wardwright@adapter_core.resolve_adapter("openclaw", "claude-cli") ==
             {"", "unsupported_runtime", "no_install", "unsupported"}

    assert :wardwright@adapter_core.resolve_adapter("openclaw", "unknown") ==
             {"", "unsupported_runtime", "no_install", "unsupported"}
  end

  test "surface fidelity only upgrades runtime-backed adapters after a surface probe passes" do
    assert :wardwright@adapter_core.surface_fidelity("runtime_verified", false) == "runtime_verified"
    assert :wardwright@adapter_core.surface_fidelity("runtime_verified", true) == "surface_verified"

    assert :wardwright@adapter_core.surface_fidelity("session_import_best_effort", true) ==
             "session_import_best_effort"

    assert :wardwright@adapter_core.surface_fidelity("prompt_handoff", true) == "prompt_handoff"
    assert :wardwright@adapter_core.surface_fidelity("unsupported", true) == "unsupported"
  end

  test "install plans default to project scope and require explicit user scope" do
    assert :wardwright@adapter_core.install_plan("installable", "project", false) ==
             "install_project_files"

    assert :wardwright@adapter_core.install_plan("installable", "user", false) ==
             "requires_explicit_user_scope"

    assert :wardwright@adapter_core.install_plan("installable", "user", true) ==
             "install_user_files"

    assert :wardwright@adapter_core.install_plan("drifted", "project", false) ==
             "repair_required"

    assert :wardwright@adapter_core.install_plan("verified", "project", false) ==
             "probe_for_stronger_verification"

    assert :wardwright@adapter_core.install_plan("verified_with_probe", "project", false) ==
             "already_verified_with_probe"

    assert :wardwright@adapter_core.install_plan("unsupported_runtime", "project", false) ==
             "no_install"
  end

  test "recording policy never applies adapted-agent auto recording to generic or unverified clients" do
    assert :wardwright@adapter_core.recording_mode(
             "manual",
             "auto",
             "manual",
             "adapter",
             "verified",
             ""
           ) == "auto"

    assert :wardwright@adapter_core.recording_mode(
             "manual",
             "auto",
             "manual",
             "adapter",
             "verified_with_probe",
             ""
           ) == "auto"

    assert :wardwright@adapter_core.recording_mode(
             "manual",
             "auto",
             "manual",
             "adapter",
             "installed_unverified",
             ""
           ) == "manual"

    assert :wardwright@adapter_core.recording_mode(
             "manual",
             "auto",
             "manual",
             "generic",
             "verified_with_probe",
             ""
           ) == "manual"

    assert :wardwright@adapter_core.recording_mode(
             "manual",
             "auto",
             "manual",
             "generic",
             "verified",
             "auto"
           ) == "auto"
  end
end

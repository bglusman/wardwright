type AdapterState {
  NotDetected
  Installable
  InstalledUnverified
  Verified
  VerifiedWithProbe
  Drifted
  UnsupportedRuntime
}

type ResolutionCoverage {
  NativeRuntime
  CoveredThroughRuntime
  SurfaceScaffold
  GatewayIdentity
}

type InstallPlan {
  InstallRuntimeAdapter
  InstallPluginScaffold
  InstallGatewayIdentity
  InstallProjectFiles
  InstallUserFiles
  RequiresExplicitUserScope
  RepairRequired
  PairOrProbe
  ProbeForStrongerVerification
  AlreadyVerifiedWithProbe
}

type Fidelity {
  TtsRuntimeProbe
  StateImportProbe
  RuntimeVerified
  SurfaceVerified
  SessionImportBestEffort
  PromptHandoff
  UnsupportedFidelity
}

type AdapterResolution {
  AdapterResolution(
    adapter_id: String,
    coverage: ResolutionCoverage,
    install_plan: InstallPlan,
    fidelity: Fidelity,
  )
  UnsupportedResolution
}

pub fn contract_version() -> String {
  "wardwright.adapter_install.v0"
}

pub fn adapter_state(
  runtime_detected: Bool,
  supported_runtime: Bool,
  installable: Bool,
  installed_files_present: Bool,
  installed_manifest_matches: Bool,
  identity_verified: Bool,
  runtime_probe_passed: Bool,
) -> String {
  classify_adapter_state(
    runtime_detected,
    supported_runtime,
    installable,
    installed_files_present,
    installed_manifest_matches,
    identity_verified,
    runtime_probe_passed,
  )
  |> state_label
}

pub fn resolve_adapter(
  surface: String,
  runtime: String,
) -> #(String, String, String, String) {
  resolve(surface, runtime)
  |> resolution_tuple
}

pub fn install_plan(
  adapter_state: String,
  scope: String,
  user_scope_explicit: Bool,
) -> String {
  case scope, user_scope_explicit {
    "user", False -> install_plan_label(RequiresExplicitUserScope)
    _, _ ->
      case install_plan_for_state(parse_adapter_state(adapter_state), scope) {
        Ok(plan) -> install_plan_label(plan)
        Error(_) -> "no_install"
      }
  }
}

pub fn recording_mode(
  default_mode: String,
  adapted_agents_mode: String,
  generic_clients_mode: String,
  client_kind: String,
  adapter_state: String,
  explicit_mode: String,
) -> String {
  case explicit_mode {
    "" ->
      case client_kind {
        "adapter" ->
          adapter_recording_mode(
            default_mode,
            adapted_agents_mode,
            parse_adapter_state(adapter_state),
          )
        "generic" -> mode_or_default(generic_clients_mode, default_mode)
        _ -> default_mode
      }
    mode -> mode
  }
}

pub fn adapter_recording_enabled(adapter_state: String) -> Bool {
  parse_adapter_state(adapter_state)
  |> adapter_state_recording_enabled
}

pub fn surface_fidelity(
  base_fidelity: String,
  surface_probe_passed: Bool,
) -> String {
  case parse_fidelity(base_fidelity), surface_probe_passed {
    RuntimeVerified, True -> fidelity_label(SurfaceVerified)
    fidelity, _ -> fidelity_label(fidelity)
  }
}

fn classify_adapter_state(
  runtime_detected: Bool,
  supported_runtime: Bool,
  installable: Bool,
  installed_files_present: Bool,
  installed_manifest_matches: Bool,
  identity_verified: Bool,
  runtime_probe_passed: Bool,
) -> AdapterState {
  case runtime_detected {
    False -> NotDetected
    True ->
      case supported_runtime {
        False -> UnsupportedRuntime
        True ->
          classify_detected_state(
            installable,
            installed_files_present,
            installed_manifest_matches,
            identity_verified,
            runtime_probe_passed,
          )
      }
  }
}

fn classify_detected_state(
  installable: Bool,
  installed_files_present: Bool,
  installed_manifest_matches: Bool,
  identity_verified: Bool,
  runtime_probe_passed: Bool,
) -> AdapterState {
  case installed_files_present, installed_manifest_matches {
    True, False -> Drifted
    True, True ->
      case identity_verified, runtime_probe_passed {
        True, True -> VerifiedWithProbe
        True, False -> Verified
        False, _ -> InstalledUnverified
      }
    False, _ ->
      case installable {
        True -> Installable
        False -> UnsupportedRuntime
      }
  }
}

fn resolve(surface: String, runtime: String) -> AdapterResolution {
  case surface, runtime {
    "omp", "omp" ->
      AdapterResolution(
        "wardwright-omp",
        NativeRuntime,
        InstallRuntimeAdapter,
        TtsRuntimeProbe,
      )
    "pi", "pi" ->
      AdapterResolution(
        "wardwright-pi",
        NativeRuntime,
        InstallRuntimeAdapter,
        StateImportProbe,
      )
    "opencode", "pi" ->
      AdapterResolution(
        "wardwright-pi",
        CoveredThroughRuntime,
        InstallRuntimeAdapter,
        RuntimeVerified,
      )
    "opencode", "omp" ->
      AdapterResolution(
        "wardwright-omp",
        CoveredThroughRuntime,
        InstallRuntimeAdapter,
        RuntimeVerified,
      )
    "opencode", "opencode-native" ->
      AdapterResolution(
        "wardwright-opencode",
        SurfaceScaffold,
        InstallPluginScaffold,
        SessionImportBestEffort,
      )
    "opencode", "codex" ->
      AdapterResolution(
        "wardwright-codex",
        GatewayIdentity,
        InstallGatewayIdentity,
        PromptHandoff,
      )
    "openclaw", "pi" ->
      AdapterResolution(
        "wardwright-pi",
        CoveredThroughRuntime,
        InstallRuntimeAdapter,
        RuntimeVerified,
      )
    "openclaw", "auto-pi" ->
      AdapterResolution(
        "wardwright-pi",
        CoveredThroughRuntime,
        InstallRuntimeAdapter,
        RuntimeVerified,
      )
    "openclaw", "codex" ->
      AdapterResolution(
        "wardwright-codex",
        GatewayIdentity,
        InstallGatewayIdentity,
        PromptHandoff,
      )
    "openclaw", "claude-cli" -> UnsupportedResolution
    _, _ -> UnsupportedResolution
  }
}

fn install_plan_for_state(
  adapter_state: AdapterState,
  scope: String,
) -> Result(InstallPlan, Nil) {
  case adapter_state, scope {
    Installable, "user" -> Ok(InstallUserFiles)
    Installable, _ -> Ok(InstallProjectFiles)
    Drifted, _ -> Ok(RepairRequired)
    InstalledUnverified, _ -> Ok(PairOrProbe)
    Verified, _ -> Ok(ProbeForStrongerVerification)
    VerifiedWithProbe, _ -> Ok(AlreadyVerifiedWithProbe)
    _, _ -> Error(Nil)
  }
}

fn adapter_recording_mode(
  default_mode: String,
  adapted_agents_mode: String,
  adapter_state: AdapterState,
) -> String {
  case adapter_state_recording_enabled(adapter_state) {
    True -> mode_or_default(adapted_agents_mode, default_mode)
    False -> default_mode
  }
}

fn adapter_state_recording_enabled(adapter_state: AdapterState) -> Bool {
  case adapter_state {
    Verified -> True
    VerifiedWithProbe -> True
    _ -> False
  }
}

fn parse_adapter_state(label: String) -> AdapterState {
  case label {
    "not_detected" -> NotDetected
    "installable" -> Installable
    "installed_unverified" -> InstalledUnverified
    "verified" -> Verified
    "verified_with_probe" -> VerifiedWithProbe
    "drifted" -> Drifted
    "unsupported_runtime" -> UnsupportedRuntime
    _ -> UnsupportedRuntime
  }
}

fn resolution_tuple(
  resolution: AdapterResolution,
) -> #(String, String, String, String) {
  case resolution {
    AdapterResolution(..) -> #(
      resolution.adapter_id,
      coverage_label(resolution.coverage),
      install_plan_label(resolution.install_plan),
      fidelity_label(resolution.fidelity),
    )
    UnsupportedResolution -> #(
      "",
      "unsupported_runtime",
      "no_install",
      "unsupported",
    )
  }
}

fn state_label(adapter_state: AdapterState) -> String {
  case adapter_state {
    NotDetected -> "not_detected"
    Installable -> "installable"
    InstalledUnverified -> "installed_unverified"
    Verified -> "verified"
    VerifiedWithProbe -> "verified_with_probe"
    Drifted -> "drifted"
    UnsupportedRuntime -> "unsupported_runtime"
  }
}

fn coverage_label(coverage: ResolutionCoverage) -> String {
  case coverage {
    NativeRuntime -> "native_runtime"
    CoveredThroughRuntime -> "covered_through_runtime"
    SurfaceScaffold -> "surface_scaffold"
    GatewayIdentity -> "gateway_identity"
  }
}

fn install_plan_label(plan: InstallPlan) -> String {
  case plan {
    InstallRuntimeAdapter -> "install_runtime_adapter"
    InstallPluginScaffold -> "install_plugin_scaffold"
    InstallGatewayIdentity -> "install_gateway_identity"
    InstallProjectFiles -> "install_project_files"
    InstallUserFiles -> "install_user_files"
    RequiresExplicitUserScope -> "requires_explicit_user_scope"
    RepairRequired -> "repair_required"
    PairOrProbe -> "pair_or_probe"
    ProbeForStrongerVerification -> "probe_for_stronger_verification"
    AlreadyVerifiedWithProbe -> "already_verified_with_probe"
  }
}

fn fidelity_label(fidelity: Fidelity) -> String {
  case fidelity {
    TtsRuntimeProbe -> "tts_runtime_probe"
    StateImportProbe -> "state_import_probe"
    RuntimeVerified -> "runtime_verified"
    SurfaceVerified -> "surface_verified"
    SessionImportBestEffort -> "session_import_best_effort"
    PromptHandoff -> "prompt_handoff"
    UnsupportedFidelity -> "unsupported"
  }
}

fn parse_fidelity(label: String) -> Fidelity {
  case label {
    "tts_runtime_probe" -> TtsRuntimeProbe
    "state_import_probe" -> StateImportProbe
    "runtime_verified" -> RuntimeVerified
    "surface_verified" -> SurfaceVerified
    "session_import_best_effort" -> SessionImportBestEffort
    "prompt_handoff" -> PromptHandoff
    _ -> UnsupportedFidelity
  }
}

fn mode_or_default(mode: String, default_mode: String) -> String {
  case mode {
    "" -> default_mode
    configured -> configured
  }
}

import gleam/list

type SurfaceFamily {
  FrameworkSdk
  LocalCodingAgent
  UnsupportedSurface
}

type SupportTier {
  RecipeOnly
  HelperPackage
  Middleware
  NativeRuntimeAdapter
  UnsupportedTier
}

type FrameworkFidelity {
  GenericOpenaiCompatible
  FrameworkReceiptCorrelated
  NativeFrameworkStateVerified
  UnsupportedFrameworkFidelity
}

type SmokeStatus {
  SmokePassed
  SmokeFailed
}

pub fn contract_version() -> String {
  "wardwright.framework_adapter.v0"
}

pub fn surface_family(surface: String) -> String {
  classify_surface(surface)
  |> surface_family_label
}

pub fn support_tier(
  recipe: Bool,
  helper_package: Bool,
  middleware_or_callback: Bool,
  native_runtime_adapter: Bool,
) -> String {
  classify_support_tier(
    recipe,
    helper_package,
    middleware_or_callback,
    native_runtime_adapter,
  )
  |> support_tier_label
}

pub fn framework_fidelity(
  generic_gateway_reaches_wardwright: Bool,
  provenance_reaches_gateway: Bool,
  receipt_visible_in_framework: Bool,
  native_framework_state_verified: Bool,
) -> String {
  classify_framework_fidelity(
    generic_gateway_reaches_wardwright,
    provenance_reaches_gateway,
    receipt_visible_in_framework,
    native_framework_state_verified,
  )
  |> framework_fidelity_label
}

pub fn smoke_status(
  model_reaches_wardwright: Bool,
  provenance_reaches_wardwright: Bool,
  receipt_visible_in_framework: Bool,
  secrets_absent: Bool,
  fallback_honest: Bool,
) -> String {
  case
    model_reaches_wardwright,
    provenance_reaches_wardwright,
    receipt_visible_in_framework,
    secrets_absent,
    fallback_honest
  {
    True, True, True, True, True -> smoke_status_label(SmokePassed)
    _, _, _, _, _ -> smoke_status_label(SmokeFailed)
  }
}

pub fn missing_smoke_requirements(
  model_reaches_wardwright: Bool,
  provenance_reaches_wardwright: Bool,
  receipt_visible_in_framework: Bool,
  secrets_absent: Bool,
  fallback_honest: Bool,
) -> List(String) {
  []
  |> require(model_reaches_wardwright, "model_reaches_wardwright")
  |> require(provenance_reaches_wardwright, "provenance_reaches_wardwright")
  |> require(receipt_visible_in_framework, "receipt_visible_in_framework")
  |> require(secrets_absent, "secrets_absent")
  |> require(fallback_honest, "fallback_honest")
  |> list.reverse
}

pub fn framework_receipt_correlation_ready(
  surface: String,
  provenance_reaches_gateway: Bool,
  receipt_visible_in_framework: Bool,
) -> Bool {
  classify_surface(surface) == FrameworkSdk
  && provenance_reaches_gateway
  && receipt_visible_in_framework
}

fn classify_surface(surface: String) -> SurfaceFamily {
  case surface {
    "vercel-ai-sdk" -> FrameworkSdk
    "langchain" -> FrameworkSdk
    "langgraph" -> FrameworkSdk
    "pydantic-ai" -> FrameworkSdk
    "openai-agents-sdk" -> FrameworkSdk
    "microsoft-extensions-ai" -> FrameworkSdk
    "semantic-kernel" -> FrameworkSdk
    "llamaindex" -> FrameworkSdk
    "jido" -> FrameworkSdk
    "jido-ai" -> FrameworkSdk
    "alloy-ex" -> FrameworkSdk
    "glopenai" -> FrameworkSdk
    "starlet" -> FrameworkSdk
    "glean" -> FrameworkSdk
    "opencode" -> LocalCodingAgent
    "openclaw" -> LocalCodingAgent
    "aider" -> LocalCodingAgent
    _ -> UnsupportedSurface
  }
}

fn classify_support_tier(
  recipe: Bool,
  helper_package: Bool,
  middleware_or_callback: Bool,
  native_runtime_adapter: Bool,
) -> SupportTier {
  case native_runtime_adapter, middleware_or_callback, helper_package, recipe {
    True, _, _, _ -> NativeRuntimeAdapter
    _, True, _, _ -> Middleware
    _, _, True, _ -> HelperPackage
    _, _, _, True -> RecipeOnly
    _, _, _, _ -> UnsupportedTier
  }
}

fn classify_framework_fidelity(
  generic_gateway_reaches_wardwright: Bool,
  provenance_reaches_gateway: Bool,
  receipt_visible_in_framework: Bool,
  native_framework_state_verified: Bool,
) -> FrameworkFidelity {
  case
    generic_gateway_reaches_wardwright,
    provenance_reaches_gateway,
    receipt_visible_in_framework,
    native_framework_state_verified
  {
    True, True, True, True -> NativeFrameworkStateVerified
    True, True, True, _ -> FrameworkReceiptCorrelated
    True, _, _, _ -> GenericOpenaiCompatible
    _, _, _, _ -> UnsupportedFrameworkFidelity
  }
}

fn surface_family_label(surface_family: SurfaceFamily) -> String {
  case surface_family {
    FrameworkSdk -> "framework_sdk"
    LocalCodingAgent -> "local_coding_agent"
    UnsupportedSurface -> "unsupported"
  }
}

fn support_tier_label(tier: SupportTier) -> String {
  case tier {
    RecipeOnly -> "recipe_only"
    HelperPackage -> "helper_package"
    Middleware -> "middleware"
    NativeRuntimeAdapter -> "native_runtime_adapter"
    UnsupportedTier -> "unsupported"
  }
}

fn framework_fidelity_label(fidelity: FrameworkFidelity) -> String {
  case fidelity {
    GenericOpenaiCompatible -> "generic_openai_compatible"
    FrameworkReceiptCorrelated -> "framework_receipt_correlated"
    NativeFrameworkStateVerified -> "native_framework_state_verified"
    UnsupportedFrameworkFidelity -> "unsupported"
  }
}

fn smoke_status_label(status: SmokeStatus) -> String {
  case status {
    SmokePassed -> "passed"
    SmokeFailed -> "failed"
  }
}

fn require(
  missing: List(String),
  present: Bool,
  capability: String,
) -> List(String) {
  case present {
    True -> missing
    False -> [capability, ..missing]
  }
}

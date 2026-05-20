import gleam/string

pub type Validation {
  Unknown
  Valid(message: String)
  Invalid(message: String)
}

pub type Draft {
  NoDraft
  Draft(
    model_id: String,
    summary: String,
    artifact_json: String,
    review_note: String,
    validation: Validation,
  )
}

pub fn none() -> Draft {
  NoDraft
}

pub fn from_agent(
  model_id: String,
  summary: String,
  artifact_json: String,
  review_note: String,
  validation_ok: Bool,
  validation_message: String,
  validated_model_id: String,
) -> Draft {
  case string.trim(artifact_json) {
    "" -> NoDraft
    artifact ->
      Draft(
        model_id: blank_default(
          validated_model_id,
          blank_default(model_id, "draft"),
        ),
        summary: summary,
        artifact_json: artifact,
        review_note: review_note,
        validation: validation_from_result(validation_ok, validation_message),
      )
  }
}

pub fn update_artifact(
  draft: Draft,
  artifact_json: String,
  validation_ok: Bool,
  validation_message: String,
  validated_model_id: String,
) -> Draft {
  let validation = validation_from_result(validation_ok, validation_message)

  case draft, string.trim(artifact_json) {
    _, "" -> NoDraft
    NoDraft, artifact ->
      Draft(
        model_id: blank_default(validated_model_id, "draft"),
        summary: validation_message,
        artifact_json: artifact,
        review_note: "Edited draft artifact. Validation runs before simulation or activation.",
        validation: validation,
      )
    Draft(_, summary, _, review_note, _), artifact ->
      Draft(
        model_id: blank_default(validated_model_id, model_id(draft)),
        summary: summary_from_validation(summary, validation_message),
        artifact_json: artifact,
        review_note: review_note,
        validation: validation,
      )
  }
}

pub fn can_activate(draft: Draft) -> Bool {
  case draft {
    Draft(validation: Valid(_), ..) -> True
    _ -> False
  }
}

pub fn can_simulate(draft: Draft) -> Bool {
  can_activate(draft)
}

pub fn has_draft(draft: Draft) -> Bool {
  case draft {
    NoDraft -> False
    Draft(..) -> True
  }
}

pub fn artifact_json(draft: Draft) -> String {
  case draft {
    NoDraft -> ""
    Draft(artifact_json:, ..) -> artifact_json
  }
}

pub fn model_id(draft: Draft) -> String {
  case draft {
    NoDraft -> ""
    Draft(model_id:, ..) -> model_id
  }
}

pub fn summary(draft: Draft) -> String {
  case draft {
    NoDraft -> ""
    Draft(summary:, ..) -> summary
  }
}

pub fn review_note(draft: Draft) -> String {
  case draft {
    NoDraft -> ""
    Draft(review_note:, ..) -> review_note
  }
}

pub fn validation_message(draft: Draft) -> String {
  case draft {
    NoDraft -> ""
    Draft(validation: Unknown, ..) -> ""
    Draft(validation: Valid(message), ..) -> message
    Draft(validation: Invalid(message), ..) -> message
  }
}

pub fn validation_label(draft: Draft) -> String {
  case draft {
    NoDraft -> ""
    Draft(validation: Valid(_), ..) -> "valid draft"
    Draft(validation: Invalid(_), ..) -> "invalid draft"
    Draft(validation: Unknown, ..) -> "unvalidated draft"
  }
}

pub fn simulation_label(draft: Draft, active_model_id: String) -> String {
  case can_simulate(draft) {
    True -> "Simulating draft " <> blank_default(model_id(draft), "draft")
    False -> "Simulating active model " <> active_model_id
  }
}

fn validation_from_result(ok: Bool, message: String) -> Validation {
  case ok {
    True -> Valid(message)
    False -> Invalid(message)
  }
}

fn summary_from_validation(
  existing_summary: String,
  validation_message: String,
) -> String {
  case string.trim(validation_message) {
    "" -> existing_summary
    message -> message
  }
}

fn blank_default(value: String, fallback: String) -> String {
  case string.trim(value) {
    "" -> fallback
    value -> value
  }
}

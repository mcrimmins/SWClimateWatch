# Local-only: rule-based preview by default; AI wording requires opt-in.
source("scripts/build-conditions-synopsis-draft.R")
source("R/conditions-synopsis-ai-comparison.R")
source("R/conditions-synopsis-relationships.R")
synopsis_stands_out_review <- build_synopsis_stands_out_review(synopsis_evidence, synopsis_draft)
print(synopsis_stands_out_review$summary, row.names = FALSE)

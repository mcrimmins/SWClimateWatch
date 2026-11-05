# Local-only. Default: request preview and template fallback, zero API calls.
# Opt in via SWC_SYNOPSIS_AI=true after configuring OPENAI_API_KEY privately.
source("scripts/build-conditions-synopsis-draft.R")
source("R/conditions-synopsis-ai-comparison.R")
synopsis_ai_comparison <- compare_conditions_synopsis_ai(synopsis_evidence, synopsis_draft)
print(synopsis_ai_comparison$summary, row.names = FALSE)

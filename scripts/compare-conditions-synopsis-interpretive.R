# Opt-in local writing experiment; separate output/cache from the ID-only pilot.
source("scripts/build-conditions-synopsis-draft.R")
source("R/conditions-synopsis-ai-comparison.R")
synopsis_ai_comparison <- compare_conditions_synopsis_ai(synopsis_evidence, synopsis_draft,
  mode = "interpretive", output_dir = "data/diagnostics/conditions-synopsis/ai-interpretive")
print(synopsis_ai_comparison$summary, row.names = FALSE)

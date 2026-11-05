# Run from the project root. Only writes the local diagnostic inventory.
# R console: source("scripts/build-conditions-synopsis-evidence.R")
# Explicit date after sourcing: build_conditions_synopsis_evidence("2026-10-05")
source("R/conditions-synopsis-evidence.R")
synopsis_evidence <- build_conditions_synopsis_evidence()

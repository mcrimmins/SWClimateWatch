# Local cached-data preview only. No downloads, API calls or site publication.
source("R/conditions-synopsis-evidence.R")
source("R/conditions-synopsis-template.R")
synopsis_evidence <- build_conditions_synopsis_evidence()
synopsis_draft <- build_conditions_synopsis_draft(synopsis_evidence, track_preview = TRUE)

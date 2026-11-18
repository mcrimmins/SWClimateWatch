# Run from the project root, ideally near the scheduled 08:00 Phoenix update.
source("R/config.R")
source("R/acis-prism.R")
source("R/audit-prism-availability.R")
prism_availability_audit <- audit_prism_availability()

# Read-only SNODAS high-SWE extent and persistence audit. No site changes.
# Run from the project root in the RStudio console.
source("scripts/load-snodas-map-pilot.R")
source("R/snodas-high-swe-audit.R")

snodas_high_swe_audit <- do.call(rbind, lapply(
  as.Date(c("2005-05-19", "2017-02-15", "2025-02-15")),
  audit_snodas_high_swe_date
))
audit_path <- file.path("data", "diagnostics", "snodas-map-pilot",
                        "high-swe-extent-persistence.csv")
utils::write.csv(snodas_high_swe_audit, audit_path, row.names = FALSE)
print(snodas_high_swe_audit)
message("Wrote local high-SWE audit: ", audit_path)

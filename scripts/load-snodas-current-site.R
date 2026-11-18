# Load the separate SNODAS data updater and current-site map workflow.
# Run from the project root; sourcing this file makes no network requests.
source("scripts/load-snodas-map-pilot.R")
source("R/snodas-daily-update.R")
source("R/snodas-seasonal-anomaly.R")
source("R/snodas-daily-comparison-pilot.R")
source("R/snodas-current-comparisons.R")
source("R/snodas-current-site.R")

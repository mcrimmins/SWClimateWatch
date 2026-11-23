source("R/nws-hazards-staging.R")
validate_nws_hazards_publication("site/daily-explorer")
validate_nws_hazards_publication("site/_site/daily-explorer")
message("PASS: source and rendered hazards, timeline totals, report data and versioned assets.")

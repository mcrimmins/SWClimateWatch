# Prepare cached maps and the standard local page/nav only. No deployment hooks.
source("scripts/load-regional-daily-reference.R")
source("R/regional-climate-site.R")
source("R/regional-precipitation-share.R")
# The accepted map caches are prerequisites. This refresh only stages the page;
# it does not repeat 30 years of daily calculations or rebuild reviewed images.
climate_region_site <- stage_regional_climate_reference_site()
print(validate_regional_climate_reference_site(rendered = FALSE))

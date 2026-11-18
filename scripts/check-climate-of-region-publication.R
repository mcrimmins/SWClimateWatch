source('scripts/load-regional-climate-release.R')
verify_regional_climate_release()
print(validate_regional_climate_reference_site(rendered=TRUE))

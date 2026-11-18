# Local-only report of published/staged weather coverage, activation and overlays.
source("R/weather-publication-audit.R")
swc_weather_publication_check<-audit_weather_publication(
  rendered_dir=file.path("site","_site","daily-explorer"))
print(swc_weather_publication_check$summary,row.names=FALSE)
message("Reports: data/diagnostics/weather-publication-status/{summary,dates}.csv")
if(identical(swc_weather_publication_check$summary$status,"FAIL"))
  stop("Weather publication check failed; inspect the report before promotion.")

# Refresh local chart styling without recomputing station references.
expressions <- parse("scripts/build-station-temperature-normals-preview.R")
for (expression in head(expressions, -1L)) eval(expression, envir = .GlobalEnv)
build_station_temperature_normals_preview(refresh_assets_only = TRUE)

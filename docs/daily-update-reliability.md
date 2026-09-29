# Daily update recovery checks

The routine update requests the configured PRISM revision dates and scans the
recent mutable window (currently 215 days) for missing dates separately for
maxt, mint, and pcpn. Existing monthly range files count as coverage for every
day they contain. Any uncovered day is added to the request plan; the normal
100-request cap and 1–1.5-second spacing still apply. With complete local
coverage, the scan adds no requests.

The updater records a small pending-map marker at
`data/diagnostics/map-rebuild-pending.txt` as soon as it finds changed
downloads, pending processing, or a forced rebuild. It removes the marker only
after the map-product stage succeeds. If a run stops during processing or map
generation, the next run will rebuild maps even when its downloads are
unchanged. The marker is not a map artifact and is ignored by Git.

These checks do not make RCC-ACIS requests by themselves. To preview the next
request list from the project root in the RStudio R console:

```r
source("R/config.R")
source("R/acis-prism.R")
update_plan <- plan_prism_download("update")
preview_prism_download(update_plan)
table(update_plan$variable)
sort(unique(as.integer(Sys.Date() - update_plan$start_date)))
```

For the next real daily update, run:

```r
Sys.setenv(SWC_UPDATE_PRISM = "true", SWC_FORCE_MAPS = "false")
update_time <- system.time(source("R/update-data.R"))
swc_update_result$summary
swc_update_result$timings[, c("stage", "status", "elapsed_seconds", "items")]
file.exists("data/diagnostics/map-rebuild-pending.txt")
Sys.unsetenv(c("SWC_UPDATE_PRISM", "SWC_FORCE_MAPS"))
```

A successful run should leave the pending marker absent. If a stage errors,
leave the marker in place and rerun after resolving the error; do not delete it
to make the update appear successful. An interrupted download or processing
stage is also safe to rerun because the manifests identify current files.
No automatic retry can recover a missing day older than the configured
lookback window without an explicit backfill.

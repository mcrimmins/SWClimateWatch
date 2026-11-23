# Daily storm reports

November 22: the report viewer, timeline and Reports in view panel passed
staging review. Daily integration is implemented and locally tested; a full
staging daily run is the next acceptance step. Production promotion is pending.

The first staging daily run refreshed 14 dates and reused 69 in 5.4 seconds.
Browser review then exposed named R lists serialized as JSON objects in report
files. The export now explicitly writes arrays, and publication validation rejects
object-shaped report collections even when counts and checksums match. Rebuild
the cached source/rendered report files and repeat staging review before promotion.

## Refresh and reuse

Set `SWC_STORM_REPORTS=true` in the appropriate VM environment file. The daily
runner requires matching destination and state settings for staging or production.
Remove the older `SWC_STORM_REPORTS_STAGING` trial flag if it was persisted.

After the Explorer and weather update, the runner refreshes the latest 14 UTC
report dates in one request. Missing older dates and failed refreshes are retried
in groups of at most 62 days, with at most three requests per run. Pending failed
refreshes remain queued even after leaving the 14-day window. Existing trial
bulk caches are imported for missing dates without downloads. Each retrieved
day replaces its entire cached list, including empty lists, so removals and
corrections are reflected. Distinct bulletins may still describe the same event;
report counts are not storm counts. Older revisions are not polled unless the
date is missing or already awaiting retry.

Coverage follows the retained Explorer dates (up to 400), plus the preceding UTC
day for precipitation-map timing. Older cache files remain local but are omitted
from the current catalog. Raw responses live in `data/raw/storm-reports/az-nm`;
verified daily caches and the retry queue live in
`data/processed/storm-reports/az-nm`. RDS files are not uploaded. No map or station
observation requests are added.

## Failures and publication

Source failures retain verified days and queue retries. Cached reports awaiting
refresh are labeled explicitly; missing days are unavailable rather than zero.
Successful empty responses remain legitimate zero-report days. Digests and a
previous verified copy protect daily cache files. PARTIAL/UNAVAILABLE report
coverage can publish alongside other site data, but invalid publication assets
stop upload. The renderer restages from cache only, avoiding a second download.
Source and rendered checks verify dates, checksums, counts, timeline summaries,
coverage and versioned browser assets before upload.

Diagnostics under `data/diagnostics/storm-reports-daily/` include
`workflow-status.csv` for the daily refresh and `publication-status.csv` for
cache-only restaging. A Storm reports line is included in the normal daily log.

## Checks and staging acceptance

```r
source("scripts/test-storm-reports-daily.R")
source("scripts/test-storm-reports-pilot.R")
source("scripts/test-storm-reports-staging.R")
```

Tests use isolated fixtures and existing caches, without live source requests or
publication. Coverage includes corrections, removals, outages/recovery, pending
retries, request caps, unavailable days, the daily hook, browser controls and
preservation of weather data.

Enable the new flag in staging.env and run the normal VM daily runner with
`SWC_PRODUCTION_CONFIG` explicitly pointing to staging.env. Use the normal runner
instead of the older trial script. After publication, load staging.env and run
`Rscript scripts/check-storm-reports-daily.R`. Review recent 1/7/30-day windows,
both timing choices, shared filters, timeline counts and Reports in view.
Inspect stale/missing counts and source errors when status is not READY.

After staging acceptance, promote the reviewed commit and enable the same flag
in production.env. The production cache can be seeded from staging while holding
both workflow locks, or bounded requests can fill it over subsequent runs.
Warning polygons remain a separate feature.

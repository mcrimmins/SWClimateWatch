# Daily NWS hazard refresh

November 23, 2026: manual staging accepted (82 Explorer dates, 2,070 events,
891 reports; source and rendered validation passed). Automatic refresh is
implemented for a full staging daily test; production promotion is pending.

Opt in with `SWC_NWS_HAZARDS=true` and `SWC_STORM_REPORTS=true`. Matching release
destination/state guards apply. The old `SWC_NWS_HAZARDS_STAGING` manual-trial
flag must be unset. Production defaults remain unchanged.

The daily workflow stages the Explorer and weather, refreshes storm reports,
then refreshes hazard archives. It reuses verified older source/processed
caches, refreshes source windows intersecting the latest 14 days and retries
failed windows on subsequent runs. Requests are bounded to six per run, each
with a 120-second timeout. Source windows are at most 31 days, including
carry-in snapshots. Changing the final endpoint creates a new cache key; it
must be verified before publishing that window. This does not backfill the
Explorer beyond its currently retained dates.

When a request fails, verified cached data can be used with a stale notice.
Pending/deferred requests persist under `data/processed/nws-hazards-daily/`.
Missing required source windows disable the optional hazard display for that
run with an explicit unavailable notice; core maps and reports continue.
Unavailable never means zero events. Missing-source errors are recorded in
the workflow report; failures after hazard assembly or during publication
validation stop the run before upload.

The site-only publication stage uses the same adapter with **downloads off**,
so render does not repeat network refreshes. Both source and rendered releases
validate coverage/cutoff, event geometry, timeline counts, report data and
versioned assets. The usual caveats remain: retrospective VTEC coverage,
30-day carry-in lookback, simplified display boundaries, incomplete message
history for county/zone hazards and incomplete coverage of non-VTEC products.

## Local verification

```r
source("scripts/test-nws-hazards-daily.R")
```

This uses the existing local preview/cache and isolated diagnostic outputs;
it never downloads or uploads. It tests refresh/retry policy with fake source
responses, request caps, recovery, cache-only restaging, preserved weather
metadata and explicit missing-source fallback. Daily-publisher and deployment
regression tests run separately.

## Full VM staging test

After checking out the new commit in the staging checkout:

```bash
bash -n scripts/test-nws-hazards-daily-staging.sh && bash scripts/test-nws-hazards-daily-staging.sh
```

This runs the normal VM preflight and full daily runner, including its lock
and timestamped log. A temporary private configuration sources staging.env
and adds the hazard/report opt-ins for this run only. It is removed afterward;
no production or permanent environment files are edited. No laptop cache
transfer is required: the existing VM hazard caches are reused.

Expect a daily summary beginning `NWS hazards: READY` (or an explicit
PARTIAL/UNAVAILABLE explanation) and a final source/rendered daily hazard
check. Inspect `data/diagnostics/nws-hazards-daily/workflow-status.csv` for
actual refresh/request/reuse/retry counts and elapsed time. Cache-only
publication results are in `publication-status.csv`. Review both timeline
rows, hazard map/table/details, dates/timing/region, quiet days, report data
and weather maps. Promotion and permanent automatic opt-in follow acceptance.

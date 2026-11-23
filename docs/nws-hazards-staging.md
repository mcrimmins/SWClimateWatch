# NWS hazards staging trial

Prepared November 23, 2026. Local review accepted; VM testing pending.
This manual trial adds archived NWS hazards to the existing Daily Explorer,
with both event-count timeline rows visible by default. It does not enable
automatic daily hazard updates or change production.

## Cache and workload

No laptop cache transfer is required. The VM reuses its existing PRISM, CORe,
Snow and normalized storm-report caches. It downloads IEM hazard archive data
for its own retained Explorer dates, including the preceding day for noon-UTC
precipitation-map alignment. Each chunk is at most 31 days, with a second query
for hazards already active at the chunk start. The source carry-in search is
limited to the preceding 30 days; older ongoing events may be absent. Non-VTEC
products are not comprehensively included. This is a retrospective archive,
not a live warning service or a record of observed impacts.

Hazard source ZIPs and verification metadata live in
`data/raw/nws-hazards/az-nm/`. Normalized, source-verified cache objects live in
`data/processed/nws-hazards-pilot/`. These directories are local caches, not Git
content. The first VM build needs network access and can take longer than a
cached rerun. Workload files are under
`data/diagnostics/nws-hazards-staging/hazards/`. A failed download stops this
trial before S3 synchronization. Do not transfer diagnostic sample pages in
place of the VM's Explorer.

## Local checks

From the project root, after building the local Explorer hazard preview:

```r
source("scripts/test-daily-explorer-nws-hazards.R")
source("scripts/test-nws-hazards-staging.R")
```

The isolated staging rehearsal uses cached local inputs, verifies the
production destination guard, all timing/region/type counts, event geometry,
report payloads and versioned browser assets. It checks weather metadata and
JSON-null preservation, plus rejection of a modified release file. It does
not write to `site/` or upload. The rehearsal requires the existing local
hazard preview and its cached source inputs.

## VM test

After checking out the intended commit in the staging checkout:

```bash
bash -n scripts/test-nws-hazards-staging.sh && bash scripts/test-nws-hazards-staging.sh
```

The script loads staging.env, verifies the exact staging destination/state,
takes the staging daily lock and prints a timestamped log path. Process-only
`SWC_NWS_HAZARDS_STAGING=true` adds hazards after normal cached Explorer and
storm-report staging. `SWC_STORM_REPORTS=true` reuses normalized report caches;
it does not download reports in this site-only run. No environment file is
modified. The ordinary render and all publication checks run before upload.
Both staged and rendered hazard releases must pass hash, geometry, timeline,
report and browser-asset validation. Synchronization does not delete S3 files.

Expected final checks include `PASS` for source and rendered hazards. Review
the staging Daily Explorer: both timeline rows, date/region/window/timing links,
map/table selection, colored type filters and All types reset, structured
details and prominent bulletin links, collapsed archive metadata, and weather
maps/means. Also test a quiet date and a wet or winter date.

This remains a manual trial. A later ordinary daily rebuild without the trial
flag restores the standard Explorer; after acceptance, integrate guarded daily
refresh/retries as a separate step before production promotion.

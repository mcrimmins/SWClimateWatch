# Expanded AZ/NM streamflow assessment

Local only: 32 selected gauges (16 per state), map, linked table and lazy-loaded
90-day hydrographs. The existing 12-gauge preview remains on port 8798; this
network uses port 8799. No production runner, environment, site or S3 changes.

## Run in the project R console

```r
options(swc.streamflow.download = TRUE)
source("scripts/assess-streamflow-network.R")
source("scripts/benchmark-streamflow-network.R")
source("scripts/test-streamflow-network.R")
source("scripts/preview-streamflow-network.R")

View(read.csv("data/diagnostics/streamflow-network-pilot/eligibility.csv"))
read.csv("data/diagnostics/streamflow-network-pilot/benchmark-history.csv")
```

Default target is yesterday in the R session's timezone. To repeat a dated trial,
set `options(swc.streamflow.network.cutoff = as.Date("2026-11-26"))` before running.
The assessment seeds the day before that target, then the live benchmark advances
one day. Both scripts are resumable; subsequent setup runs reuse verified inputs
and should not be interpreted as a new cold-download measurement.

`scripts/replay-streamflow-network.R` replays the target from verified caches,
with downloads disabled. It is labeled `cache_replay` and never qualifies as a
successful live-runtime benchmark. The live benchmark requires downloads enabled.

## Policy and eligibility

The additional gauges cover tributaries, geographic gaps and mainstem/managed
flow context. `network-plan.csv` lists all gauges and selection roles. Dam context
is flagged for Lees Ferry, San Juan near Archuleta and below Elephant Butte.
Other gauges still need a regulation/diversion interpretation review.

Daily source metadata must identify a located stream gauge in its expected state
and one current primary daily-mean discharge series in cubic feet per second.
Retired primary series are excluded when multiple primary series exist; concurrent
ambiguity is withheld. Historical samples are matched to that daily series;
disjoint or predecessor series are not silently spliced together.

`ELIGIBLE` requires a numeric observation within three days of cutoff, 330 or more
supported calendar days, and at least 30 approved observations for the latest
observation's calendar day. This is a sample-support criterion, not a guarantee of
30 complete water years or unregulated flow. Gauges with shorter historical support
remain visible as `OBSERVATIONS_ONLY`, with unavailable historical categories.

Bootstrap retains 90 days of selected daily observations. Incremental updates
request the last 14 days, extended back to the previous successful endpoint after
a longer gap. A successful response replaces its entire revision interval, so a
removed source value cannot survive as an obsolete observation. Zeros, missing
days, qualifiers and conflicts retain their existing meanings. Old observations
outside the 90-day window are discarded from the processed state.

Each processed gauge state has a SHA-256 verification file. Failed requests retain
verified observations and the previous successful endpoint, with an explicit
refresh-failed label. Corrupt or mismatched state is not used as a fallback.
Daily runs use a 45-second source budget and 60-request ceiling. The 60-second
runtime target requires all 32 source refreshes, no initial-history repairs, no
metadata downloads and no historical-statistics downloads. Deferred/failed work
does not receive a passing runtime result merely because the script finished fast.

Metadata and historical statistics are reused during the benchmark. A production
integration still needs a bounded slower refresh schedule for those sources,
VM timing and publication validation. This pilot does not enable automatic updates.

## Laptop measurement, November 27, 2026

Target: daily observations through November 26. All 32 gauges built successfully.
Thirty meet historical-support checks. Santa Cruz at Tucson (28 approved values
for the displayed calendar day) and Animas below Aztec (20) remain observations-only.

| Phase | Elapsed | OGC requests | Statistics requests | Response-body bytes |
| --- | ---: | ---: | ---: | ---: |
| Setup, reusing existing 12-gauge metadata/statistics | 37.2 s | 72 | 20 | 3,682,705 |
| Live next-day incremental update | 18.9 s | 32 | 0 | 248,827 |

The live update reused all metadata, requested only 14-day windows and met the
60-second local target. These are laptop measurements, not a VM runtime promise.
Bytes describe downloaded response bodies, not wire-level transfer overhead.
The initial browser assets and network summary are about 220 KB; all 32 enriched
hydrographs total about 920 KB, fetched individually on selection. Basemap tiles
are separate requests.

Reports live under `data/diagnostics/streamflow-network-pilot`: `eligibility.csv`,
`benchmark-history.csv`, `last-run.csv` and per-mode `*-gauges.csv`. The changed-date
count includes new dates, revised values and dates aged out of the retained window.

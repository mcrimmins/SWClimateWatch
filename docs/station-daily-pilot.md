# Daily RCC-ACIS station pilot

This is a **research audit**, not a published station product or a daily site
update. The [annual station inventory](station-inventory.md) screened 164
long-record candidates. This pilot examines daily values and provenance for
15 geographically distributed fixed stations in Arizona and New Mexico, plus
the Phoenix, Tucson, and Albuquerque ThreadEx area series as separate
comparisons. The fixed-station selection is explicit in
`R/acis-station-daily-pilot.R`; it is not an automatic public-station list.

## Run and outputs

From the project root:

```r
source("scripts/audit-acis-daily-pilot.R")
swc_acis_daily_pilot_result$stations[, c("name", "role", "daily_status")]
```

The default audits at most two new series per run. Repeat the command to
resume, or set `SWC_ACIS_DAILY_PILOT_MAX = "18"` for the whole pilot. Full
daily responses are read into memory, summarized, and discarded; they are not
saved locally. Small, resumable summaries are ignored by Git and written to
`data/diagnostics/acis-stations/daily-pilot/`:

- `pilot-stations.csv`: selection, coordinates, role, annual-coverage screen,
  and daily audit state.
- `summary.csv`: period coverage, longest missing runs, latest-data lag,
  trace/flag counts, and source-identifier counts for each variable.
- `annual.csv` and `monthly.csv`: observed/missing days, traces, special flags,
  and accumulation flags. Monthly rows cover 1991–2020 and the latest ten
  completed calendar years.
- `sources.csv` and `flags.csv`: counts and date ranges by ACIS source ID, and
  counts of the raw ACIS flags. A source-ID change is a review cue, **not**
  proof of a site move or data inhomogeneity.
- `checks.csv`: maximum temperature below minimum temperature and negative
  precipitation counts.

The audit requests the full metadata-defined daily history for `maxt`, `mint`,
and `pcpn`, with ACIS `f` (flag) and `i` (source station ID) additions. It
validates that ACIS returned one row per calendar day. `M` is missing. A
precipitation `T` flag is counted as an observed trace even when ACIS returns
the numeric value zero. `S`/`A` flag subsequent/accumulated amounts; those
days must **not** be treated as independent daily event amounts for extreme
indices. The `special_flag_days` count excludes routine `M` and `T` markers;
the raw flag table preserves every code. See the
[ACIS web-service definitions](https://docs.rcc-acis.org/acisws/) and the
[Regional Climate Center flag explanation](https://w3.rcc-acis.org/services/blog/2020/02/24/).

The latest-ten-year check uses the ten *completed* calendar years; the
latest-data lag is measured against the day before the audit. Each summary
row includes its `as_of` date, since a pilot resumed on a later day can mix
audit dates. This script never updates the website or publishing workflow.

## Findings from the September 29, 2026 review

All 18 series were audited without a request, parsing, date-sequence, or
temperature/precipitation sign-check failure. The initial 15 fixed stations
remain useful as a spatial pilot, but daily-level screening changes how a few
should be used:

| Series | Daily-review finding | Consequence for first products |
|---|---|---|
| Cliff 11 SE | Latest valid values were August 31, 28 days behind the September 28 check date. | Historical reference only until current reporting resumes; do not label it a current station. |
| Chama | A 90-day precipitation gap occurred April 1–June 29, 2021; latest-ten-year precipitation coverage is about 94%. | Apply period-specific completeness rules to precipitation ranks and rolling totals. |
| Yuma Proving Ground | A 212-day gap spans October 2008–April 2009 in all three variables, although latest-ten-year coverage is above 99%. | Exclude incomplete windows/years from full-record comparisons, not the entire station. |
| Nogales 6 N | Latest-ten-year coverage is about 99%/99%/99% for max/min/precipitation, but the longest recent temperature gap is 12 days. | Require complete observed windows for short-period products. |

The pilot's ThreadEx series have excellent coverage, but their composite
histories and absent point coordinates mean they should appear as clearly
labeled area series in a table/chart, not as fixed observation-site map dots.

## Next design gate

Before public maps, tables, percentiles, or WMO-style indices, specify
variable- and period-specific completeness requirements. In particular:

1. Show station name, identity, source, last observation, and sample size.
2. Use the existing 1991–2020 period for departures from normal; if rankings
   use each station's full usable record, display its changing start year and
   valid sample count.
3. Compute 7/30/90-day precipitation only from complete periods and handle
   trace, subsequent, and accumulated flags explicitly.
4. Suppress or mark stale current observations, and review source/component
   history before claiming homogeneous long-record trends or extremes.
5. Keep ThreadEx comparisons distinct from point stations in the interface.

No public station product has been approved or integrated into the daily
publish cycle at this stage.

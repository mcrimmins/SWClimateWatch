# Climate Perspectives station-network comparison

This is the next research step toward a broad station map and table. It does
**not** add stations to the public website or its daily publish job. The
[daily pilot](station-daily-pilot.md) remains the reviewed starting network.
The September 28, 2026 maximum-temperature and precipitation CSV exports from
[SERCC Climate Perspectives](https://sercc.oasis.unc.edu/Map.php?region=wrcc)
serve as a **dated coverage benchmark**, not a permanent authority on which
stations should be shown. The comparison reads the exports without copying
their climate values into this project.

## Run the bounded comparison and audit

From the project root in an R console, point `exports` to the two downloaded
CSVs. The reader keeps `Station` as text so leading zeroes survive.

```r
source("R/config.R")
source("R/acis-station-inventory.R")
source("R/acis-station-reference-network.R")

exports <- c(
  "C:/Users/Crimmins/Downloads/rcp_20260928_1DAY.csv",
  "C:/Users/Crimmins/Downloads/rcp_20260928_1DAY (1).csv"
)

# No ACIS requests: inspect the existing metadata and annual-coverage cache.
preview <- run_acis_reference_network(exports, max_new_stations = 0L)
table(preview$network$state, preview$network$annual_audit)
preview$pending

# On a machine with ACIS access: resolve border-area ThreadEx records and
# audit up to 25 previously unaudited station records. Rerun to resume.
audited <- run_acis_reference_network(
  exports,
  max_new_stations = 25L,
  refresh_missing_threadex = TRUE
)
audited$pending
audited$failures
```

The report is `data/diagnostics/acis-stations/reference-network/network.csv`.
It contains one row per exported ID within the project's existing padded map
bounding box. Several exported IDs may resolve to one ACIS unified record, so
the number of *rows* can exceed the number of annual audits. Annual coverage
uses the existing checksum-free, resumable UID cache in
`data/diagnostics/acis-stations/annual-coverage/`. The broad comparison is
separate from the original 70-year, three-variable shortlist and does not
rewrite that selection or its 18-series daily pilot.

The first local preview of these snapshots found 65 export IDs in the map
footprint. Cached ACIS metadata matched 62; the three absent records were
Alamosa, Las Vegas (Nevada), and El Paso ThreadEx area series. Those area
series do not have true station-point coordinates in the original ACIS
inventory. The targeted `refresh_missing_threadex` lookup obtains them by
ThreadEx ID. It does not use the point shown in the exported CSV as the physical
location of a composite series.

## Interpret the report

- `match_method` records whether the export ID was matched by ACIS ID/state,
  disambiguated using coordinates, or left unmatched. It resolves reused
  historical IDs such as the Tucson Airport/WBO segments without silently
  choosing the first ACIS record.
- `in_long_record_shortlist` and `in_daily_pilot` describe the existing work;
  neither is an automatic publication decision.
- For each of `maxt`, `mint`, and `pcpn`, `*_metadata_20year_screen` means the
  ACIS date span is at least 20 years and the metadata endpoint is within two
  years. This only decides which records merit closer review.
- `*_years_90pct` counts completed calendar years with at least 90% observed
  days. `*_20year_annual_screen` requires 20 such years **and** the metadata
  screen. Its value is missing until an annual audit is available. Counts for
  1991–2020 and the latest ten completed years are separate columns.
- `map_longitude` and `map_latitude` are blank for ThreadEx. A ThreadEx record
  is an area composite and needs a distinct map symbol or table treatment.

These are screening metrics, not certification for percentiles or extremes.
The [Climate Perspectives methods](https://sercc.oasis.unc.edu/about.php)
describe a 20-year parameter-specific minimum and 90% period-data rule; our
event and percentile products will need their **own** complete-window rules.
Before publishing a station for a particular metric, check daily recency,
source/component changes, precipitation trace and accumulation flags, and the
valid historical sample for that exact calendar window. Always show the
station's valid sample count and period of record alongside a rank or
percentile. A station may qualify for one variable or product but not another.

## Daily-quality audit of the broad network

After the annual audit is complete, the next command reviews each **unique
ACIS record** once. The September 29 export resolves to 62 records because
Carefree/Cave Creek, Hot Springs/Truth or Consequences, and Selsor Ranch/Wolf
Canyon share ACIS unified IDs. The daily audit reuses the 13 already completed
pilot summaries, leaving 49 records for new requests in the first preview.
Run small batches or set a larger cap for an unattended local run:

```r
source("R/config.R")
source("R/acis-station-inventory.R")
source("R/acis-station-daily-pilot.R")
source("R/acis-station-reference-network.R")
source("R/acis-station-reference-daily-audit.R")

daily_preview <- run_acis_reference_daily_audit(max_new_stations = 0L)
daily_preview$pending

# One local run can cover the remaining records; rerun after any interruption.
daily_audit <- run_acis_reference_daily_audit(max_new_stations = 49L)
daily_audit$pending
daily_audit$failures
```

The small outputs are under
`data/diagnostics/acis-stations/reference-network/daily-audit/`:
`stations.csv`, `summary.csv`, `annual.csv`, `monthly.csv`, `sources.csv`,
`flags.csv`, and `checks.csv`. Each station's summary cache is reusable; full
daily responses are discarded. `stations.csv` preserves all reference IDs
associated with a single ACIS record and the summary's `as_of` date. The
audit captures latest-observation lag, missing runs, source changes, trace
days, and accumulated precipitation flags. These are review evidence, not
automatic acceptance for every station metric. It is not part of the daily
site publication workflow.

## Planned sequence after the broad audit

1. Review the broad daily-audit results for geographic gaps, stale records,
   accumulated precipitation, and source/component changes. Decide which
   station-variable combinations can serve current conditions.
2. Define product-specific completeness and recency rules, then build a
   station map and sortable table of current 30-day precipitation and mean
   temperature conditions. Show missing or stale values explicitly.
3. Add historical percentile ranks from each station's valid same-season
   samples, with the changing sample size and record period visible.
4. Add a small set of extremes indices after flag handling, daily event
   completeness, and station-history review are tested. Never infer that the
   broad coverage screen alone makes an extreme defensible.

None of these research jobs are part of the daily site update yet.

## Current-conditions research prototype

The first map-and-table prototype is implemented in
`R/acis-station-current-prototype.R` and run with
`scripts/build-acis-station-current-prototype.R`. It is **not** in the public
site navigation or daily publishing job. It requests each unique ACIS record
once to make a compressed daily cache under
`data/processed/acis-stations/reference-network/daily/`. Later runs request
the most recent 45 days again to capture revisions. An interrupted run resumes
with the remaining station records; a stale cache also fills any gap before its
refresh window. The cache retains numeric values, flags, trace/accumulation
markers, and source IDs for later percentile and extremes work. Full-record
downloads are needed once per station; the previous daily audit retained only
summaries, not the underlying daily series.

From the project root, preview the number of pending caches without downloading:

```r
Sys.setenv(SWC_ACIS_STATION_MAX = "0")
source("scripts/build-acis-station-current-prototype.R")
swc_acis_station_prototype$pending
```

Then run a small batch, or do all 62 unique records in one resumable local run:

```r
Sys.setenv(SWC_ACIS_STATION_MAX = "62")
source("scripts/build-acis-station-current-prototype.R")
swc_acis_station_prototype$pending
swc_acis_station_prototype$failures
```

When `pending` reaches zero, open
`data/diagnostics/acis-stations/current-prototype/index.html` locally. It has
two station-point maps and a sortable table. Its `station-status.csv` companion
includes per-product missing and flagged-day counts for review. The page does
not require Quarto or deployment. For a specified observation date, set
`SWC_ACIS_STATION_AS_OF` to `YYYY-MM-DD`; otherwise the script uses yesterday.
Unset overrides afterward with
`Sys.unsetenv(c("SWC_ACIS_STATION_MAX", "SWC_ACIS_STATION_AS_OF"))`.

The first products are the sum of daily precipitation and the average of daily
`(maxt + mint) / 2` over the **same 30 consecutive calendar days**, ending on
the displayed as-of date. A value is available only when every required daily
observation is present, numeric, within the broad plausible range, and free of
non-trace flags. For mean temperature, both maximum and minimum must be valid
each day, and maximum cannot be below minimum. Trace precipitation is zero;
accumulated (`A`) and accumulation-start (`S`) precipitation cannot be assigned
to an individual day and invalidates that window. ACIS explains those flags in
its [station-data guidance](https://w3.rcc-acis.org/services/blog/2020/02/24/).
A missing day is labeled
`INCOMPLETE`, a quality/accumulation issue `FLAGGED`, and a cache not updated
through the requested date `STALE`. No incomplete value is plotted or silently
treated as zero. Fixed stations are points; ThreadEx area composites appear
only in the table, never as precise station coordinates. These conservative
prototype rules can be adjusted by product after review; they do not certify
historical percentile or extremes samples.

# PRISM data acquisition and climatology methods

This document is the technical reference for the Southwest Climate Watch PRISM
workflow. It records the decisions that determine what is downloaded, how API
traffic is limited, how rasters are processed, and how climatological products
are calculated. Keep it synchronized with the scripts under `R/` when methods
change.

## Data source and spatial domain

- Source: RCC-ACIS web services, using the PRISM grid exposed by the
  [GridData service](https://www.rcc-acis.org/docs_webservices.html).
- Primary product: daily maximum temperature (`maxt`), minimum temperature
  (`mint`), and precipitation (`pcpn`). Monthly data may later support products
  that do not require daily timing, but it is not used to calculate the daily
  thresholds described here.
- Area of interest: Arizona and New Mexico plus a 0.5-degree buffer on every
  side. The request bounding box is west -115.60, south 30.75, east -102.45,
  north 37.60 degrees, identified in the cache as `az-nm-pad050`.
- Grid: native PRISM 1/24-degree geographic grid (EPSG:4326). ACIS aligns the
  requested box to grid cells, so the returned raster extent can be slightly
  larger than the request box.
- Units: native ACIS values are retained throughout the workflow: degrees
  Fahrenheit for temperature and inches for precipitation.

The Grid2 endpoint returns GeoTIFF only when one element is requested. Each
calendar-month request therefore contains one variable, and each daily value is
stored as a separate GeoTIFF band. Band dates are read from GDAL `Date`
metadata rather than inferred from layer order alone.

## Periods of record

The archive period and statistical baselines serve different purposes and must
not be treated as synonyms.

| Purpose | Fixed period | Use |
|---|---:|---|
| Stable local daily archive | 1981-01-01 through 2025-12-31 | Full stable PRISM daily record available at the time of implementation; supports rankings, alternate baselines, and future products. |
| Operational recent cache | 2026 onward | Refreshed separately because recent PRISM grids can be revised. It is not silently added to a fixed historical baseline. |
| Standard normals | 1991-01-01 through 2020-12-31 | Daily means, standard deviations, departures, and other products intended to use the current 30-year climate normal. |
| Standard percentile thresholds | 1991-01-01 through 2020-12-31 | Fixed baseline for comparable heat/cold extreme indices. A centered five-day window provides about 150 temperature observations per calendar-day threshold. |
| Supplemental long-record percentiles | 1981-01-01 through 2020-12-31 | Sensitivity product with about 200 temperature observations per five-day threshold. It must be labeled as a long-record baseline rather than a 30-year normal. |
| Record rankings | 1981 through the latest stable year | Rank current conditions against all stable observations. |

The full archive is intentionally longer than the normal period. Extending the
download does not make thresholds use an expanding baseline: product baselines
remain explicit and fixed, which keeps maps comparable through time.

PRISM describes daily data beginning in 1981 and notes that recent values are
revised on a schedule. See the [PRISM data page](https://prism.oregonstate.edu/data/)
and [update calendar](https://prism.oregonstate.edu/calendar/) before changing
the stable archive end date.

## Temperature daily climatologies and percentiles

For each non-leap calendar day, the calculation pools observations in a
centered five-day calendar window: the target day, the two preceding days, and
the two following days. The calendar is circular, so the January 1 window also
uses December 30 and 31. With 30 complete baseline years this supplies roughly
150 observations for a threshold rather than only 30.

Supported temperature statistics are `mean`, `sd`, `median`, `p10`, and `p90`.
Percentiles use R quantile type 8. The baseline is 1991-2020 unless another
period is passed explicitly. A 1981-2020 run is the documented long-record
sensitivity product.

Observed February 29 values are excluded from fitting the 365 daily threshold
curves. A February 29 output layer is inserted by averaging the fitted February
28 and March 1 layers. A complete daily climatology therefore has 366 layers
named, for example, `maxt_p90_07-15`, and time coordinates use leap reference
year 2000.

The five-day method follows the general approach used for calendar-day climate
extreme thresholds. It reduces sampling noise without converting the product
into a moving or expanding climatological baseline.

### Current-value percentile ranks

`calculate_prism_percentile_rank()` produces an exact current `maxt` or `mint`
percentile-rank raster on a 0-100 scale. It reads only the approximately 150
baseline layers in the applicable centered five-day window, compares the
current value with that local distribution independently at every grid cell,
and uses the inverse of the type-8 interpolation/plotting position. Values below
or above the complete baseline sample are assigned 0 or 100. Ties use their
average rank. February 29 is the average of ranks against the February 28 and
March 1 reference windows, paralleling the interpolated leap-day thresholds.

This is calculated on demand from local processed files, so it requires no ACIS
request and avoids storing 101 percentile grids for every calendar day. Daily
precipitation is intentionally excluded: its zeros and skewed distribution are
better represented by wet/dry status, wet-day amount ranks, and rolling-total
percentiles.

## Precipitation climatologies and percentiles

A wet day is precipitation greater than or equal to **0.04 inch**, the
native-inch representation used here for the approximately 1 mm wet-day
threshold. `wet_frequency` is the fraction of valid observations meeting this
threshold in the centered five-day calendar window.

Precipitation amount percentiles are deliberately named `wet_p90`, `wet_p95`,
and `wet_p99`. They are calculated from all wet-day amounts in the requested
baseline, not from zero-heavy all-day values, and use R quantile type 8. These
are annual wet-day thresholds and therefore produce one raster layer rather
than 366 calendar-day layers. Calling an ambiguous precipitation `p90` is
rejected.

Daily precipitation `mean`, `sd`, and `median` remain available using the
centered five-day calendar window. Future map products should also emphasize
rolling 7-, 30-, and 90-day precipitation totals and departures; those rolling
accumulation functions are not yet implemented.

## Download planning, throttling, and recovery

Historical downloads use one calendar-month file per variable. The complete
1981-2025 plan has 1,620 requests: 45 years x 12 months x 3 variables.
Month-sized files make individual revisions recoverable and avoid overlap.

API protection is built into `download_prism_plan()`:

- requests are strictly sequential;
- the default delay is 1 second plus up to 0.5 second random jitter;
- no more than 100 requests run unless the caller explicitly changes the cap;
- the local archive wrapper defaults to 25 requests per batch;
- transient HTTP failures are retried by `httr2`;
- every response is validated as a dated, single-variable GeoTIFF before use;
- files are moved into place atomically;
- the manifest is updated after every successful request;
- completed files are skipped, so interrupted batches resume safely.

`preview_prism_download()` and `summarize_prism_bootstrap()` are read-only and
should be used before a large batch. They report completed, scheduled, and
deferred requests.

## Storage and provenance

```text
data/raw/prism/az-nm-pad050/daily/archive/{variable}/YYYY-MM-DD_YYYY-MM-DD.tif
data/raw/prism/manifest.csv

data/processed/prism/az-nm-pad050/daily/archive/{variable}/YYYY-MM-DD_YYYY-MM-DD.tif
data/processed/prism/manifest.csv

data/processed/prism/az-nm-pad050/climatology/{start}-{end}/daily/
  {variable}/{method}/{statistic}.tif
data/processed/prism/climatology/manifest.csv
```

The method component prevents a centered five-day product from overwriting a
one-day or annual-wet-day product. Examples are `centered-05day` and
`annual-wet-days`.

Raw, processed, and climatology manifests record paths and MD5 checksums.
Processed files also record the source checksum, so a revised raw file is
automatically marked for rebuilding. Climatology records include the source
signature, baseline dates, method, window size, quantile type, wet-day
threshold, units, build time, byte size, and output checksum. A single manifest
contains rows for many variables, statistics, and periods; one manifest per
climatology output is neither expected nor desired.

## Script and function reference

### `R/config.R`

- `swc_paths`, `swc_region`, and `swc_prism` hold paths, AOI, units, periods,
  percentile settings, revision ages, and request limits.
- `check_swc_packages()` checks runtime dependencies.
- `initialize_swc_directories()` creates the raw, processed, and map folders.

### `R/acis-prism.R`

- `validate_prism_variables()` and `normalize_prism_bbox()` validate inputs.
- `split_prism_date_range()` creates non-overlapping monthly or daily chunks.
- `plan_prism_download()` creates a bootstrap or recent-update request plan
  without contacting ACIS.
- `prism_daily_payload()` converts one plan row to a Grid2 request.
- `prism_geotiff_dates()` and `validate_prism_geotiff()` verify response dates,
  band count, geometry, and format.
- `replace_file_atomically()` safely installs a completed temporary file.
- `prism_manifest_path()`, `read_prism_manifest()`, and
  `write_prism_manifest()` maintain download provenance.
- `prepare_prism_request_queue()`, `format_prism_plan_summary()`, and
  `preview_prism_download()` apply and report the request cap.
- `download_prism_plan()` performs bounded, throttled, retryable downloads.
- `sync_prism()` is the high-level planner/downloader for bootstrap or update
  mode.

### `R/process-prism.R`

- `prism_raster_dates()` reads and validates GeoTIFF dates.
- `validate_prism_native_values()` rejects values outside conservative native-
  unit plausibility bounds.
- `read_prism_daily_raster()` attaches dates, stable layer names, and units.
- `prism_processed_manifest_path()` and `prism_processed_path()` define outputs.
- `plan_prism_daily_processing()` compares raw and processed checksums and marks
  new or revised files for processing.
- `write_prism_processed_raster()` writes compressed, tiled GeoTIFFs safely.
- `process_prism_daily_plan()` processes only rows marked for refresh.

### `R/build-prism-climatology.R`

- `read_prism_daily_collection()` selects, geometry-checks, orders, and
  optionally completeness-checks processed daily inputs.
- `prism_calendar_keys()` defines the 365- or 366-day reference calendar.
- `validate_prism_window()` requires a positive odd window size.
- `prism_statistic_method()` creates the method namespace used in paths.
- `prism_apply_daily_statistic()` calculates one pooled daily statistic.
- `prism_centered_daily_statistic()` applies the circular centered window.
- `prism_insert_feb29()` interpolates the leap-day output.
- `prism_wet_day_percentile()` calculates annual wet-day precipitation
  thresholds.
- `prism_climatology_statistic()` validates and dispatches a statistic.
- `prism_climatology_units()` records native or fractional output units.
- `prism_climatology_path()` constructs a period- and method-specific path.
- `prism_climatology_manifest_path()` locates the shared climatology manifest.
- `build_prism_daily_climatology()` builds outputs and records provenance. It
  reports input-loading time, every 25th completed calendar day by default, and
  elapsed time for each statistic. Set `progress_every` to another positive
  integer or use `quiet = TRUE` to suppress messages.

### `R/prism-percentile-rank.R`

- `prism_reference_window_dates()` identifies the baseline dates in the
  centered calendar window, including year-boundary and leap-day behavior.
- `read_prism_daily_subset()` opens only monthly processed files containing the
  requested dates and checks completeness and geometry.
- `prism_type8_percentile_rank()` calculates one median-unbiased type-8 rank.
- `prism_percentile_rank_raster()` applies that rank cell-by-cell.
- `select_prism_current_layer()` selects and validates one dated current layer.
- `calculate_prism_percentile_rank()` is the high-level on-demand function and
  can optionally write the result to `output_path`.

### `R/prism-workflow.R`

- `summarize_prism_bootstrap()` reports archive progress without downloads.
- `run_prism_bootstrap_batch()` downloads at most 25 monthly files by default,
  processes all pending files, and returns a status table.

## RStudio console workflow

Start every session with the project loaded and source the workflow:

```r
source(file.path("R", "config.R"))
source(file.path("R", "acis-prism.R"))
source(file.path("R", "process-prism.R"))
source(file.path("R", "build-prism-climatology.R"))
source(file.path("R", "prism-percentile-rank.R"))
source(file.path("R", "prism-workflow.R"))
```

Inspect the full archive plan without making a request:

```r
archive_plan <- plan_prism_download("bootstrap")
preview_prism_download(archive_plan, max_requests = 25)
summarize_prism_bootstrap(archive_plan, max_requests = 25)
```

Download and process one conservative batch:

```r
batch <- run_prism_bootstrap_batch(max_requests = 25)
batch$status
```

Build standard temperature thresholds only after the complete 1991-2020
processed collection is present:

```r
maxt_thresholds <- build_prism_daily_climatology(
  variable = "maxt",
  baseline_start = swc_prism$percentile_start,
  baseline_end = swc_prism$percentile_end,
  statistics = c("mean", "sd", "p10", "p90")
)
```

Build a separately labeled long-record sensitivity threshold:

```r
maxt_long_thresholds <- build_prism_daily_climatology(
  variable = "maxt",
  baseline_start = swc_prism$long_percentile_start,
  baseline_end = swc_prism$long_percentile_end,
  statistics = c("p10", "p90")
)
```

Build precipitation wet-day products:

```r
pcpn_thresholds <- build_prism_daily_climatology(
  variable = "pcpn",
  baseline_start = swc_prism$percentile_start,
  baseline_end = swc_prism$percentile_end,
  statistics = c("wet_frequency", "wet_p90", "wet_p95", "wet_p99")
)
```

Calculate a current maximum-temperature percentile rank from an already
processed monthly raster. If the file contains a month, `current_date` selects
the desired layer:

```r
maxt_rank <- calculate_prism_percentile_rank(
  current = "data/processed/prism/az-nm-pad050/daily/archive/maxt/2025-12-01_2025-12-31.tif",
  variable = "maxt",
  current_date = as.Date("2025-12-31")
)

range(terra::values(maxt_rank), na.rm = TRUE)
```

Do not set `require_complete = FALSE` for published climatologies. That option
is only for small development trials.

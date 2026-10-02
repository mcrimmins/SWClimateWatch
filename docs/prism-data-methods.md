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
- Derived product: daily mean temperature (`tmean`) is calculated locally as
  `(maxt + mint) / 2` at each grid cell. It is never requested from RCC-ACIS.
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

Maximum and minimum temperature are the downloaded source variables. Daily
mean temperature is their cell-by-cell arithmetic average. Its daily normal is
the arithmetic average of the corresponding maximum- and minimum-temperature
normal layers, which is mathematically equivalent to averaging all historical
daily mean temperatures. Exact mean-temperature percentile ranks instead use
the historical daily `(maxt + mint) / 2` samples because percentiles cannot be
reconstructed by averaging separate maximum- and minimum-temperature
percentiles.

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

`calculate_prism_percentile_rank()` produces an exact current `maxt`, `mint`,
or derived `tmean` percentile-rank raster on a 0-100 scale. It reads only the approximately 150
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

### Thirty-day mean-temperature departure

The persistent-temperature product averages the latest 30 locally derived
daily mean-temperature grids and subtracts the average of the 30 normal layers
for those same calendar dates. Each normal layer comes from the centered
five-day 1991-2020 mean climatology. This is equivalent to averaging the 30
daily departures, but the implementation retains the observed-period and
matching-normal means as explicit parts of the calculation. The output remains
in degrees Fahrenheit and requires no additional RCC-ACIS request.

The operational map uses a fixed -15 to 15 degree F diverging scale so updates
remain comparable. Values outside that display range are retained in the
GeoTIFF and shown at the end colors on the map.

### Rolling mean-temperature percentile ranks

The operational 7-, 30-, and 90-day products first calculate the arithmetic
mean of all derived daily mean-temperature layers in the complete trailing
period. The resulting period mean is ranked cell-by-cell against historical
period means ending near the same calendar date in 1991-2020. The centered
five-day ending-date window supplies approximately 150 historical rolling
means for each comparison. The method deliberately ranks the multi-day mean;
it does not average daily percentile ranks.

Historical rolling means are cached separately for each duration and ending
calendar day. Cache files use 64-bit floating-point storage to preserve close
values and avoid artificial empirical-rank ties. Reuse requires a matching
cache version and a source signature covering both maximum- and minimum-
temperature inputs. When a validated previous-calendar-day cache is available,
the next cache is calculated exactly as `(previous mean * duration - outgoing +
incoming) / duration`, reading only the two boundary-day temperature pairs.
Parent paths and checksums are retained in the manifest. Missing or stale
parents fall back to a direct build. February 29 follows the daily-rank
convention by averaging ranks against the February 28 and March 1 reference
groups and is built directly.

### Thirty-day extreme warm-day frequency

An extreme warm day is one whose maximum temperature is strictly greater than
the local calendar-day 90th-percentile threshold. Each threshold is fitted from
the centered five-day 1991-2020 sample using R quantile type 8. The operational
product counts qualifying days in the latest complete 30-day period. Equality
with the threshold is not counted as an exceedance.

Under a stationary climate, approximately three exceedances are expected in a
30-day period. The observed count is therefore more useful than a simple hot
day/no-hot-day flag for identifying persistent unusual heat. The GeoTIFF and
map use integer day counts from 0 through 30 and require no additional API
request.

### Thirty-day extreme cold-night frequency

The companion cold-night product counts days whose minimum temperature is
strictly less than the local calendar-day 10th-percentile threshold. It uses
the same centered five-day 1991-2020 samples, type-8 quantiles, complete 30-day
window, and 0-30 count scale as the warm-day product. Equality with the
threshold is not counted. Approximately three qualifying nights are expected
in 30 days under stationary conditions.

### Thirty-day freeze count

The freeze product counts days in the latest complete 30-day period whose
minimum temperature is less than or equal to 32 degrees F. Equality is
included because this is a physical threshold rather than an empirical
percentile. The map uses a fixed 0-30 night scale and is retained year-round,
although interpretation is most useful during autumn, winter, and spring. No
climatological reference is implied by the count itself; a matching freeze-day
anomaly is reported as a separate companion product.

The freeze-night anomaly subtracts the matching 1991-2020 average 30-day
count from the current count. Historical samples use the centered five-day
ending-date window, providing approximately 150 reference periods. Negative
values mean fewer freeze nights than average; positive values mean more. The
map uses a fixed -10 to 10 night diverging scale, while the GeoTIFF retains
values outside those display endpoints.

Historical freeze counts are cached by duration, threshold, baseline, seasonal
window, and ending calendar day. Within each baseline year, adjacent reference
periods are updated by dropping the outgoing daily indicator and adding the
incoming indicator. This produces exactly the same counts as independent sums
while avoiding 150 full rolling calculations. Cache reuse requires a matching
version and processed-source signature.

### First-freeze date and departure

The seasonal first-freeze analysis finds the first day whose minimum
temperature is less than or equal to 32 degrees F in each August 1-July 31
season. The stored value is a 1-based day offset from August 1. The operational
date map converts that offset back to calendar-date labels, while the departure
map subtracts the median 1991-2020 first-freeze offset. Negative departures are
early and positive departures are late.

The baseline cache contains one first-freeze layer for each of the 30 seasons
beginning in 1991 through 2020. A grid cell's median normal is considered
reliable only when at least 80 percent of those seasons (24 of 30) recorded a
freeze; lower-frequency cells are masked on the departure map. Current-season
cells that have not yet frozen are blank on both maps.

Publishing uses a second coverage rule so an almost-empty early-autumn map
does not replace a useful completed-season map. A new season is eligible no
earlier than September 1 and only after at least 5 percent of historically
freeze-prone cells have an observed first freeze. Until then, stable `latest`
PNGs retain the previous completed season. The season cache is stored under
`data/processed/prism/az-nm-pad050/climatology/19910101-20201231/first-freeze-samples/`,
and analysis rasters are stored under
`data/processed/prism/az-nm-pad050/seasonal/first-freeze/mint/`.

### Last-freeze date and departure

The companion last-freeze analysis records the final day at or below 32
degrees F in the same August 1-July 31 cold season. Its 1-based offset from
August 1 makes the departure calculation directly comparable across leap and
non-leap seasons. Departure is the observed offset minus the median 1991-2020
offset, so negative values are early and positive values are late.

The last-freeze cache contains one layer per baseline season and uses the same
80-percent reliability rule as first freeze. Cells without a freeze are blank.
Current-season maps begin publishing March 1 and are labeled as observations
so far because a later freeze can still update the date. They become final
after July 31. From August through February, the stable `latest` PNGs retain
the previous completed season. Cache files are stored under
`data/processed/prism/az-nm-pad050/climatology/19910101-20201231/last-freeze-samples/`,
and operational rasters are stored under
`data/processed/prism/az-nm-pad050/seasonal/last-freeze/mint/`.

### Freeze-free season length and departure

For each calendar year, freeze-free season length is the elapsed day difference
between the last minimum temperature at or below 32 degrees F during
January 1-July 31 and the first at-or-below-32 F minimum during August 1-
December 31. Both bookends are required; cells without either event are `NA`.
This avoids assigning an artificial length to places that remain frost-free.

The normal is the median length across 1991-2020 and is retained only where at
least 80 percent of baseline years (24 of 30) have both freeze dates. Departure
is current length minus median length, so negative values are shorter and
positive values are longer. Current-year maps are eligible after September 1
and after at least 5 percent of historically reliable cells have both observed
bookends. They remain provisional through December 31; otherwise the stable
`latest` files retain the preceding completed year.

The 30-layer baseline cache is stored under
`data/processed/prism/az-nm-pad050/climatology/19910101-20201231/freeze-free-samples/`,
and operational rasters are stored under
`data/processed/prism/az-nm-pad050/seasonal/freeze-free/mint/`.

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
centered five-day calendar window. Operational maps now include observed 1-,
7-, and 30-day precipitation totals. Recent single-day revision files take
precedence over an overlapping monthly catchup file. Each accumulation requires
a complete, consecutive sequence of dates and retains inches as the native unit.
Because these are observed totals rather than climatological comparisons, their
map footers report the accumulation period instead of a reference period.

Current 7- and 30-day totals also receive exact 0-100 percentile ranks against
1991-2020 rolling totals. The reference sample uses accumulation periods ending
within the centered five-day calendar window around the current ending date,
providing about 150 baseline totals per grid cell. All totals, including zeros,
participate in the ranking; ties receive their average type-8 plotting-position
rank. February 29 follows the temperature convention by averaging ranks against
the February 28 and March 1 reference windows. These ranks are calculated on
demand from local processed daily files and do not contact RCC-ACIS.

## Download planning, throttling, and recovery

Historical downloads use one calendar-month file per variable. The complete
1981-2025 plan has 1,620 requests: 45 years x 12 months x 3 variables.
Month-sized files make individual revisions recoverable and avoid overlap.

After the fixed archive is installed, `catchup` mode uses one range request per
variable and complete calendar month between the archive end and the last day
of the previous month. The current partial month is intentionally excluded so
its filename does not change every day. Run catchup once before the first
operational update. Thereafter, `update` mode downloads the missing current-
month dates and the configured PRISM revision-age dates as single-day payloads.
This separates efficient bulk transfer from small routine updates.

The nine revision ages are checked for all three downloaded variables, so a
routine run can contain 27 small refresh requests even when the newest common
date has not advanced. The downloader records the checksum before and after
each refresh. `run_swc_daily_update()` rebuilds processed rasters and maps only
when at least one downloaded file changed or `SWC_FORCE_MAPS=true` was
explicitly set. Byte-identical refresh downloads therefore preserve PRISM's
revision checks without triggering an archive-wide checksum scan, processing,
or a multi-minute map cycle. The daily workflow instead performs a fast
manifest-to-manifest comparison using the checksums already recorded at
download time. This retains recovery of raw files left unprocessed by an
interrupted run. Direct calls to `plan_prism_daily_processing()` continue to
rehash source files by default for a full integrity check; the operational
updater explicitly selects the manifest-based fast path.

The revision ages are 2, 6, 31, 61, 92, 123, 153, 184, and 215 days. The
215-day revisit is deliberately after PRISM's approximate six-month final
release window: an age-based 184-day request can precede a month-batched final
revision. This safeguard does not inspect PRISM's last-modeled timestamp and
does not capture later major dataset revisions automatically.

Daily stage timings are appended to
`data/diagnostics/daily-update-timings.csv`, and `update_enabled_prism_maps()`
records one row per map group in
`data/diagnostics/map-update-timings.csv`. These reports make cache construction,
map rendering, and future performance regressions visible without changing any
scientific output.

API protection is built into `download_prism_plan()`:

- requests are strictly sequential;
- the default delay is 1 second plus up to 0.5 second random jitter;
- no more than 100 requests run unless the caller explicitly changes the cap;
- the local archive wrapper defaults to 25 requests per batch;
- transient HTTP failures are retried by `httr2`;
- every response is validated as a dated, single-variable GeoTIFF before use;
- files are moved into place atomically;
- the manifest is updated after every successful request;
- completed non-refresh files are skipped, so interrupted batches resume safely;
  configured revision-age files are deliberately checked again for upstream
  corrections.

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
data/processed/prism/accumulation-cache-manifest.csv
data/processed/prism/rolling-temperature-cache-manifest.csv

data/processed/prism/az-nm-pad050/climatology/{start}-{end}/
  rolling-samples/pcpn/{duration}/{method}/{MM-DD}.tif
data/processed/prism/az-nm-pad050/climatology/{start}-{end}/
  rolling-temperature-samples/tmean/{duration}/{method}/{MM-DD}.tif

site/maps/generated/prism/temperature/{variable}-percentile-rank-{date}.png
site/maps/generated/prism/temperature/{variable}-percentile-rank-latest.png
site/maps/generated/prism/temperature/{variable}-{value,departure}-{date}.png
site/maps/generated/prism/temperature/{variable}-{value,departure}-latest.png
site/maps/generated/prism/temperature/{maxt,mint,tmean}-departure-30day-latest.png
site/maps/generated/prism/temperature/tmean-percentile-rank-{07,30,90}day-latest.png
site/maps/generated/prism/precipitation/pcpn-total-{01,07,30,90}day-latest.png
site/maps/generated/prism/precipitation/pcpn-percentile-rank-{07,30,90}day-latest.png
site/maps/generated/prism/precipitation/pcpn-longest-dry-spell-180day-latest.png
site/maps/generated/prism/precipitation/pcpn-longest-dry-spell-percentile-rank-180day-latest.png
site/maps/generated/prism/precipitation/pcpn-wet-day-count-090day-latest.png
site/maps/generated/prism/precipitation/pcpn-wet-day-count-percentile-rank-090day-latest.png
site/maps/generated/prism/precipitation/pcpn-wet-day-intensity-090day-latest.png
site/maps/generated/prism/precipitation/pcpn-wet-day-intensity-percentile-rank-090day-latest.png
site/maps/generated/prism/precipitation/pcpn-water-year-max-03day-latest.png
site/maps/generated/prism/precipitation/pcpn-water-year-max-percentile-rank-03day-latest.png
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

- `validate_prism_variables()`, `validate_prism_analysis_variables()`,
  `validate_prism_temperature_variables()`, and `normalize_prism_bbox()`
  distinguish downloaded variables from locally derived analysis variables.
- `split_prism_date_range()` creates non-overlapping monthly or daily chunks.
- `plan_prism_download()` creates a bootstrap, complete-month catchup, or
  recent-update request plan without contacting ACIS.
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
  mode, including one-time catchup mode.

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
- `prism_wet_day_percentiles()` calculates multiple annual wet-day thresholds
  in one archive pass; requesting `wet_p90`, `wet_p95`, and `wet_p99` together
  avoids three expensive reads and sorts of the complete baseline.
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
- `prism_mean_temperature_raster()` derives dated mean-temperature layers;
  `read_prism_temperature_subset()` assembles either source or derived
  temperature reference samples.
- `prism_type8_percentile_rank()` calculates one median-unbiased type-8 rank.
- `prism_percentile_rank_raster()` applies that rank cell-by-cell.
- `select_prism_current_layer()` selects and validates one dated current layer.
- `calculate_prism_percentile_rank()` is the high-level on-demand function and
  can optionally write the result to `output_path`.

### `R/map-southwest.R` and `R/build-current-prism-maps.R`

- `southwest_state_boundaries()` returns Arizona and New Mexico polygons.
- `southwest_raster_map()` masks a grid to the states and applies a consistent
  map layout; `save_southwest_map()` writes the image.
- `latest_common_prism_date()` finds the newest single-day recent raster shared
  by the requested variables.
- `prism_recent_processed_path()`, `prism_percentile_rank_output_path()`, and
  `prism_percentile_map_path()` define stable operational paths.
- `prism_current_temperature_raster()` reads maximum or minimum temperature and
  derives mean temperature without an API call.
- `prism_temperature_normal_layer()` derives the mean-temperature normal from
  the matching maximum- and minimum-temperature normals.
- `prism_temperature_normal_raster()` selects several matching daily normals
  with one climatology read per source variable.
- `calculate_prism_rolling_temperature_departure()` and
  `build_current_temperature_rolling_departure_map()` calculate and publish one
  30-day temperature departure.
- `build_current_temperature_rolling_departure_maps()` uses one common ending
  date to publish the maximum-, minimum-, and mean-temperature maps together.
  Maximum temperature represents sustained afternoon conditions, minimum
  temperature represents sustained nighttime conditions, and mean temperature
  summarizes both.
- `R/prism-rolling-temperature-percentile.R` builds and validates historical
  rolling mean-temperature caches, calculates exact type-8 percentile ranks
  for the latest 7-, 30-, and 90-day means, and publishes the dated and stable
  `latest` maps. Cache provenance includes both maximum- and minimum-
  temperature source checksums.
- `prism_temperature_threshold_raster()` selects matching calendar-day p10 or
  p90 threshold layers without repeatedly opening the climatology.
- `calculate_prism_temperature_extreme_frequency()` and
  `build_current_extreme_warm_day_frequency_map()` count and publish maximum-
  temperature p90 exceedances during the latest 30 days. The same calculation
  supports strict below-threshold comparisons, and
  `build_current_extreme_cold_night_frequency_map()` publishes minimum-
  temperature p10 undershoots.
- `prism_freeze_day_count_raster()`, `calculate_prism_freeze_day_count()`, and
  `build_current_freeze_day_count_map()` count and publish minimum temperatures
  at or below 32 degrees F during the latest 30 days.
- `calculate_prism_freeze_day_anomaly()` and
  `build_current_freeze_day_anomaly_map()` compare the current count with the
  matching centered-five-day 1991-2020 average.
- `prism_freeze_season_start()` assigns observations to August 1-July 31
  seasons; `prism_first_freeze_from_raster()` finds the first at-or-below-32 F
  day in each grid cell.
- `build_prism_first_freeze_cache()` creates or reuses the 30-season baseline;
  `prism_first_freeze_climatology()` calculates freeze frequency and the
  reliable median first-freeze day.
- `calculate_prism_first_freeze_products()` writes the current observed and
  departure rasters. `build_current_prism_first_freeze_maps()` publishes dated
  and stable maps only after the date and coverage rules are satisfied.

### `R/prism-last-freeze.R`

- `prism_last_freeze_from_raster()` finds the final at-or-below-32 F day in a
  complete or partial August-July cold season.
- `build_prism_last_freeze_cache()` creates or reuses the 30-season sample;
  `prism_last_freeze_climatology()` applies the 80-percent reliability mask and
  calculates the median day.
- `calculate_prism_last_freeze_products()` writes observed and departure
  rasters. `build_current_prism_last_freeze_maps()` publishes provisional maps
  beginning March 1 and retains the completed season during August-February.

### `R/prism-freeze-free-season.R`

- `prism_freeze_free_length_from_raster()` calculates the elapsed days between
  the last January-July freeze and first August-December freeze.
- `build_prism_freeze_free_cache()` creates or reuses one layer for each
  calendar year in 1991-2020; `prism_freeze_free_climatology()` applies the
  80-percent reliability mask and calculates the median length.
- `calculate_prism_freeze_free_products()` writes length and departure rasters.
  `build_current_prism_freeze_free_maps()` publishes once the September 1 and
  5-percent coverage thresholds are met and otherwise retains the completed
  year.
- `build_current_temperature_value_maps()` and
  `build_current_temperature_departure_maps()` write observed and anomaly maps
  in degrees Fahrenheit.
- `build_prism_percentile_rank_map()` uses a fixed 0–100 scale with emphasized
  10th and 90th percentile tails.
- `build_current_temperature_percentile_maps()` calculates current ranks and
  writes both dated and stable `latest` PNG files used by Quarto.

### `R/build-current-prism-precipitation-maps.R`

- `select_prism_daily_sources()` and `read_prism_best_daily_range()` select one
  best available grid per date, preferring revised recent files over monthly
  catchup files.
- `prism_accumulation_from_raster()` calculates complete 1-, 7-, 30-, or 90-day
  totals; `build_current_precipitation_maps()` writes the operational rasters
  and maps.
- `prism_rolling_source_dates()` and `prism_rolling_totals_for_end_dates()`
  assemble the baseline rolling-total sample.
- `calculate_prism_accumulation_percentile_rank()` calculates exact current
  7-, 30-, or 90-day percentile ranks against the fixed seasonal baseline.
- `build_current_precipitation_percentile_maps()` writes dated and stable
  `latest` percentile-rank maps.
- `build_current_precipitation_percentile_change_map()` subtracts the 30-day
  rank from 14 days earlier from the current 30-day rank. Each endpoint uses
  the centered five-day 1991-2020 reference sample appropriate to its own
  ending calendar day. Positive percentile-point changes indicate wetting and
  negative changes indicate drying. The current 30-day rank remains the
  companion map because change alone does not describe current conditions.
- `calculate_prism_accumulation_percent_normal()` divides the current total by
  the mean of the matching centered five-day cached sample. The 0.10-inch
  minimum-normal threshold is shared with the water-year products.
- `build_current_precipitation_percent_normal_maps()` writes dated and stable
  `latest` maps for 30- and 90-day percent of normal.

### `R/prism-accumulation-cache.R`

- `prism_accumulation_cache_path()` keys rolling historical samples by
  duration, baseline, centered seasonal window, and ending calendar day.
- `prism_accumulation_source_signature()` fingerprints the exact processed
  source grids used by a cache.
- `read_prism_accumulation_cache()` validates cached layer dates.
- `build_prism_accumulation_cache()` creates or reuses a historical sample and
  records its source signature, dimensions, build time, byte size, and checksum.
  Cache samples use versioned 64-bit floating-point storage so near-equal
  accumulation values do not become artificial ties in empirical ranks.
- A validated next-calendar-day cache uses the exact recurrence `previous -
  outgoing day + incoming day`. The manifest records the parent path and
  checksum. Missing, stale, or February 29 parents fall back to a direct build.

### `R/prism-temperature-threshold-cache.R`

- `prism_freeze_count_cache_path()` keys historical count samples by threshold,
  duration, baseline, seasonal window, and ending calendar day.
- `prism_rolling_counts_for_end_dates()` calculates the first rolling count in
  each baseline year directly and advances adjacent ending dates with exact
  drop/add updates.
- `build_prism_freeze_count_cache()` validates source checksums, creates or
  reuses the 1991-2020 sample, and records cache provenance in a separate
  manifest.
- `calculate_prism_accumulation_percentile_rank()` uses the cache by default;
  set `use_cache = FALSE` only for direct-method validation.

### `R/prism-water-year-cache.R`

- `prism_water_year()` assigns October-December dates to the following water
  year; `prism_water_year_start()` returns the corresponding October 1.
- `prism_water_year_reference_periods()` interprets the standard 1991-2020
  baseline as water years 1991 through 2020. Thus, the first input period begins
  October 1, 1990 rather than January 1, 1991.
- `prism_water_year_cache_path()` keys the historical sample by baseline and
  target calendar day. Every sample contains 30 water-year-to-date layers.
- `build_prism_water_year_cache()` validates source checksums and reuses a
  current sample. When the preceding calendar-day cache is current, it adds
  only the newly required historical daily layers; otherwise it builds the
  requested sample directly. October 1 is always a direct one-day reset.
- Incremental records include the parent cache path and checksum. All samples
  use versioned `FLT8S` storage to avoid artificial percentile ties.
- February 29 retains all 30 reference water years by interpolating each
  water year's cumulative February 28 and March 1 totals. It is built directly,
  as are March 1 updates immediately following a leap day.

Build or reuse the current target-calendar-day reference sample from RStudio:

```r
source(file.path("R", "prism-water-year-cache.R"))

water_year_cache <- build_prism_water_year_cache(
  target_date = as.Date("2026-09-09")
)

water_year_cache$build_method
terra::nlyr(water_year_cache$raster)
range(water_year_cache$periods$water_year)
```

The first late-water-year build must read nearly the whole 30-year baseline.
It reports completed water years at the configured progress interval. Once the
previous calendar-day cache exists, a normal daily update reads only the newly
required historical daily layers, while still checking the parent's source
signature and file checksum.

### `R/build-current-prism-water-year-maps.R`

- `prism_current_water_year_total()` accumulates the current processed daily
  grids from October 1 through the selected date.
- `prism_water_year_comparison_rasters()` calculates the matching 1991-2020
  mean, percent of normal, and empirical type-8 percentile rank from the compact
  30-layer historical cache.
- Percent of normal is masked where the matching historical mean is below 0.10
  inch. This prevents unstable percentages early in the water year or in very
  dry grid cells; the total and percentile products remain available there.
- `calculate_current_prism_water_year_products()` writes four analysis rasters:
  current total, matching normal, percent of normal, and percentile rank.
- `build_current_prism_water_year_maps()` writes dated and stable `latest` PNGs
  for total, percent of normal, and percentile rank. The maps retain the full
  PRISM footprint and the shared state, county, city, logo, and footer design.

Build all three operational maps with:

```r
source(file.path("R", "build-current-prism-water-year-maps.R"))
water_year_maps <- build_current_prism_water_year_maps()
water_year_maps
```

### `R/prism-dry-spell.R`

- A wet day is a grid-cell precipitation amount greater than or equal to 0.04
  inch. `prism_trailing_dry_length()` counts consecutive sub-threshold days
  backward from an ending date, so a wet ending day has length zero.
- `build_prism_dry_spell_cache()` builds a 150-layer seasonal sample from the
  centered five-day windows for 1991-2020. It starts with a 365-day lookback and
  doubles the lookback whenever any valid grid cell reaches the search limit.
  A cache is written only after the censor count is zero.
- The September 9 reference sample required a 730-day lookback; its longest
  historical grid-cell spell is 552 days. This demonstrates why silently
  capping the calculation at one year would be inappropriate for this region.
- A normal next-calendar-day cache uses the exact recurrence `0` on a wet day
  and `previous length + 1` on a dry day. It reads only the 150 new historical
  ending-day layers after validating the previous cache and its source
  signature. February 29 transitions build directly.
- `calculate_prism_dry_spell_products()` writes the current length and its
  empirical type-8 seasonal percentile rank. The displayed length scale is
  capped at 90+ days, but the analysis raster retains the uncapped count.
- `build_current_prism_dry_spell_maps()` writes dated and stable `latest` maps.
  The length map uses green for recently wet areas and red for long dry spells;
  the percentile map uses blue for unusually short and red for unusually long
  spells.

### `R/prism-longest-dry-spell.R`

- `prism_longest_dry_spell_from_raster()` finds the maximum consecutive run
  below the 0.04-inch wet-day threshold within a complete trailing window. The
  operational window is 180 days; a value of 180 means no qualifying wet day
  occurred anywhere in that window.
- The moving period is intentional. A water-year maximum in Arizona and New
  Mexico would commonly retain the normally dry spring long after it stopped
  describing recent conditions.
- `build_prism_longest_dry_spell_cache()` builds 150 seasonally matched
  historical samples: 30 baseline years times the centered five-day ending-date
  window. Cache identity includes the duration, threshold, baseline, method,
  source signature, output checksum, and target calendar day.
- The five consecutive ending dates for each baseline year are evaluated in one
  raster pass. This grouped exact calculation reduces the normal build from 150
  full archive passes to approximately 30; it does not approximate the dry-run
  statistic.
- When Rcpp and a working local C++ toolchain are available, the grouped pass
  uses the equivalent compiled window calculation in
  `src/prism-longest-dry-spell.cpp`. If compilation is unavailable, it uses the
  tested R calculation; the threshold, missing-data rule, and resulting maps
  do not change. Compilation happens once per R session, not for every cell.
- `calculate_prism_longest_dry_spell_products()` writes the current count and
  its empirical type-8 percentile rank. The percentile compares like with like:
  historical 180-day windows ending at the same time of year.
- `build_current_prism_longest_dry_spell_maps()` writes dated and stable
  `latest` count and percentile maps. The first cache for a calendar day is a
  direct build; subsequent runs reuse it while its inputs and checksum remain
  current.

### `R/prism-wet-day-count.R`

- `prism_wet_day_count_from_raster()` counts grid-cell days with precipitation
  greater than or equal to 0.04 inch during a complete trailing period. The
  operational duration is 90 days.
- `build_prism_wet_day_count_cache()` builds 150 historical 90-day counts: 30
  baseline years times the centered five-day ending-date window. The cache is
  keyed by duration, threshold, baseline, method, and target calendar day and
  records source signatures and checksums in a separate manifest.
- A validated next-calendar-day cache updates as `previous - outgoing wet day +
  incoming wet day`, so routine updates read at most the two boundary-day sets
  rather than reconstructing all 150 historical periods. February 29
  transitions build directly.
- `calculate_prism_wet_day_count_products()` writes the observed count and its
  empirical type-8 percentile rank. `build_current_prism_wet_day_count_maps()`
  writes dated and stable `latest` maps using the common footprint, boundaries,
  cities, logo, and footer.
- Wet/dry comparisons allow a numerical tolerance of 0.0000001 inch solely to
  prevent a decimal value stored as float32 just below 0.04 from being
  misclassified. The scientific threshold remains 0.04 inch.

### `R/prism-wet-day-intensity.R`

- `prism_mean_wet_day_intensity()` averages only amounts on days meeting the
  0.04-inch threshold. Sub-threshold trace amounts are excluded rather than
  being divided among the qualifying events.
- The operational product uses a complete trailing 90-day window and requires
  at least one wet day. Cells with no wet day are `NA`, not zero intensity.
- `build_prism_wet_day_intensity_cache()` builds 150 historical samples: 30
  baseline years times the centered five-day ending-date window. The cache key
  and manifest record duration, wet-day threshold, minimum count, baseline,
  method, source signature, checksum, and target calendar day.
- With the operational minimum of one wet day, a validated next-day cache
  reconstructs the previous wet-day sum from its intensity and count, subtracts
  the outgoing qualifying amount, and adds the incoming qualifying amount. It
  uses validated wet-day-count parents and records parent provenance. Other
  minimum counts, missing parents, and February 29 transitions build directly.
- `calculate_prism_wet_day_intensity_products()` writes the current inches per
  wet day and its empirical type-8 percentile rank. The percentile uses the
  same seasonally matched ending-date convention as the accumulation and
  wet-day-count products.
- `build_current_prism_wet_day_intensity_maps()` writes dated and stable
  `latest` intensity and percentile maps. A current cache is reused when its
  source signature and checksum remain valid.

### `R/prism-very-wet-contribution.R`

- `read_prism_very_wet_threshold()` loads the single-layer annual `wet_p95`
  threshold calculated from 1991-2020 wet days of at least 0.04 inch.
- `prism_very_wet_contribution_from_raster()` sums precipitation on days
  strictly above the local p95 threshold, divides by all precipitation in the
  complete trailing 90-day window, and multiplies by 100. A zero is retained
  when precipitation occurred but no day exceeded p95; totals below 0.10 inch
  are `NA`.
- `build_prism_very_wet_contribution_cache()` builds 150 seasonally matched
  reference shares. Cache identity includes the daily source checksums,
  threshold checksum and statistic, duration, minimum total, baseline,
  centered window, output checksum, and target calendar day.
- A validated next-day cache reconstructs the prior threshold-qualified amount,
  updates that numerator and the total with the outgoing and incoming days, and
  then recomputes the percentage. It reuses validated rolling-accumulation
  parents, records parent provenance, and falls back to the direct method when
  validation is incomplete or on a February 29 transition.
- `calculate_prism_very_wet_contribution_products()` writes the current share
  and empirical type-8 percentile rank. `build_current_prism_very_wet_contribution_maps()`
  publishes dated and stable `latest` maps.

### `R/prism-water-year-maximum.R`

- `prism_complete_water_year_periods()` defines 30 complete October 1 through
  September 30 periods labeled WY1991-WY2020. The first baseline input date is
  therefore October 1, 1990.
- `prism_maximum_rolling_total()` forms every complete rolling three-day total
  in a period and retains the largest value at each grid cell. Partial one- or
  two-day windows at the start of a water year are not used.
- `build_prism_water_year_maximum_cache()` builds one maximum layer per
  complete baseline water year and stores the 30-layer sample as `FLT8S` with a
  version, processed-source signature, byte size, and checksum. Because the
  standard baseline is fixed, routine daily updates reuse this cache.
- `prism_current_water_year_maximum()` calculates the maximum-so-far from the
  active water year's October 1 through the latest date.
- `calculate_current_prism_water_year_maximum_products()` writes the observed
  maximum and its empirical type-8 rank against complete historical maxima.
  The active-year rank is provisional until September 30 because additional
  events can only maintain or increase the current maximum.
- `build_current_prism_water_year_maximum_maps()` writes dated and stable
  `latest` maps. The observed map is capped visually at 8+ inches while the
  raster retains uncapped values.
- `prism_water_year_precipitation_concentration_raster()` divides the active
  water year's maximum three-day total by its total precipitation and
  multiplies by 100. Cells with water-year totals below 0.10 inch are masked,
  and valid values are bounded to 0-100 percent.
- `build_current_prism_water_year_concentration_map()` reuses the existing
  maximum and total rasters when available and publishes dated and stable
  `latest` maps. High percentages indicate precipitation dominated by one
  event; low percentages indicate a more distributed event history.

Build or reuse the cache and create both maps:

```r
source(file.path("R", "prism-water-year-maximum.R"))

maximum_3day_maps <- build_current_prism_water_year_maximum_maps()
maximum_3day_maps

concentration_map <- build_current_prism_water_year_concentration_map()
concentration_map
```

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

After the fixed archive is complete, catch up complete months once before
starting daily updates:

```r
catchup_plan <- plan_prism_download("catchup")
preview_prism_download(catchup_plan, max_requests = 25)
catchup_downloads <- download_prism_plan(catchup_plan, max_requests = 25)
process_prism_daily_plan(plan_prism_daily_processing())
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

Build the current 90-day wet-day count and percentile maps:

```r
source(file.path("R", "map-southwest.R"))
source(file.path("R", "build-current-prism-maps.R"))
source(file.path("R", "build-current-prism-precipitation-maps.R"))
source(file.path("R", "prism-accumulation-cache.R"))
source(file.path("R", "prism-wet-day-count.R"))

wet_day_maps <- build_current_prism_wet_day_count_maps()
wet_day_maps
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

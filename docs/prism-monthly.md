# Monthly PRISM development

November 6, 2026: the regional access/cache pilot is implemented and tested.
This is true monthly PRISM, not monthly files containing daily layers. Nothing
is connected to the daily publisher, cron, site navigation, or S3 yet.

## Run the access pilot on the laptop

From the project root in the RStudio console:

```r
source("scripts/run-prism-monthly-access-pilot.R")
monthly_pilot_summary
monthly_pilot_pairs
```

The sample requests January 1895, January 1991, July 2020, and the latest
completed calendar month. Each month has monthly mean maximum temperature,
monthly mean minimum temperature (degrees F), and monthly precipitation total
(inches). Mean temperature will be derived from the temperature pair in the
analysis increment; it is not another request.

Run the same script again to confirm zero-download cache reuse. Failed requests
are recorded; the script stops after writing reports if any inputs remain
unverified or a temperature pair fails. Rerun to resume. No maps are generated.

Reports are under `data/diagnostics/prism-monthly-access-pilot/`:

- `summary.csv`: verification, saved size, and elapsed time for the latest run.
- `inventory.csv`: input paths, request signatures, and cache completion.
- `last-run.csv`: attempted downloads, timings, sizes, and errors.
- `temperature-pairs.csv`: cells where monthly maximum is below minimum.

Sample measured November 6: 12/12 regional files verified in 18.73 seconds,
1.42 MiB of compressed inputs. A cache-only repeat took 2.83 seconds with no
requests. Historical and current samples matched the existing daily PRISM grid
geometry. These measurements do not predict map/statistical processing time.

## Source, validation, and storage

Use the [RCC-ACIS GridData service](https://docs.rcc-acis.org/acisws/) at
`https://grid2.rcc-acis.org/GridData`, grid `prism` (also accepts `21`), with explicit monthly
interval/duration and sum or mean reductions, explicit units, and zero allowed
missing inputs. The older `data.rcc-acis.org` endpoint returned a dataset error
for the January 1895 precipitation probe; do not automatically switch to another
dataset or fall back to daily-derived monthly values.

Downloads request only the configured AZ/NM padded bounding box. Validate the
month stamp, one layer, geographic CRS, 1/24-degree spacing, regional extent,
cross-file geometry, finite values and plausible Fahrenheit/inch ranges. At
least half the padded rectangle must have valid values; this is an access-pilot
gross-failure guard, not a final statistical support rule. Missing cells outside
the source domain remain missing.

Only compressed regional GeoTIFFs and a separate manifest are retained under
`data/processed/prism-monthly/az-nm-pad050/`. Temporary uncompressed responses
are removed. The manifest records request identity, units, source response MD5,
saved file MD5, ranges, support, sizes, and fetch time. Verified existing inputs
are skipped; corrupt or differently requested files are downloaded again.
Refreshes validate before replacing an existing file. A failed refresh retains
the old grid. Do not run concurrent writers against this cache.

## Bounded historical batches

After reviewing the access pilot, a chosen historical range can be planned and
downloaded using the same functions. This is a manual development operation,
not the final scheduled monthly updater:

```r
source("scripts/load-prism-monthly.R")
monthly_plan <- plan_prism_monthly_download(start = "1895-01", end = "1895-12")
table(monthly_plan$complete)
monthly_batch <- download_prism_monthly_plan(monthly_plan, max_requests = 12L)
monthly_batch
```

Re-create the plan before each batch so it sees newly verified inputs. The
default is 12 requests, with one second between requests. Increase the explicit
cap or use `Inf` only when ready for a longer download. All three variables are
required for the initial shared precipitation/temperature products. Cache
presence alone does not mean a multi-month analysis or baseline is complete.

## Remaining increments and operating policy

### Full-cache audit and 12-month temperature pilot

The user completed all **4,746 monthly grids for January 1895-October 2026**.
Run the full audit in RStudio from the project root:

```r
source("scripts/audit-prism-monthly-cache.R")
monthly_cache_audit$summary
subset(monthly_cache_audit$months, status != "PASS")
```

This checks checksums/request identities, month stamps, values, geometry against
a common grid, maximum versus minimum temperature, one-sided temperature
availability, and size. Reports are in
`data/diagnostics/prism-monthly-cache-audit/`. Verified audit records are reused
when the current input checksums and common geometry still match; progress is
saved every 25 months. The audit never downloads or changes input grids.
An unpaired temperature cell is reported as a warning and excluded from derived
temperature windows; a physically inverted pair, invalid grid or missing input
fails the audit. Warning counts are cell-month counts, not distinct cells.

After a passing audit, build the pilot:

```r
source("scripts/run-prism-monthly-temperature-pilot.R")
monthly_temperature_pilot$summary
browseURL(normalizePath(monthly_temperature_pilot$paths[["map"]]))
```

The pilot reuses unchanged audit records but recomputes its statistics. It
creates a local PNG and diagnostic GeoTIFFs in
`data/diagnostics/prism-monthly-temperature-pilot/`, including current mean
temperature, warm/cold ranks, percentile, comparison sample size, and
1991-2020 mean/departure/support. It also writes comparison windows, source
audit signatures, methods, timing and support counts. There is no website or
publication integration yet; outputs are overwritten on another pilot run.

For October 2026, compare complete November-October windows ending in
**1896-2026 (131 windows)**. Derive each monthly mean temperature as
`(monthly maxt + monthly mint) / 2`; average monthly means using actual month
lengths, including leap days. Every month must be usable at a cell; gaps are
not filled. Each eligible ending year contributes once, including the current
year. Average ranks handle ties (within 1e-8 F); warm rank 1 is warmest and cold
rank 1 is coldest. The plotted full-record percentile is
`100 * (count lower + 0.5 * count tied) / n`, rather than the daily fixed-reference
type-8 percentile calculation. It is not SPI or an extreme-day metric.

Require at least 30 valid windows and 90% of eligible windows per cell for ranks
(118 of 131 for this pilot). The 1991-2020 companion departure requires at least
27 of those 30 matching windows. The map's middle class means the middle of the
long record; it does not imply zero departure from the recent normal. A plotted
rank is a rank of PRISM's modeled regional grid-cell history, not a station
record. Full-history statistical support and the 1991-2020 normal are kept
separate. Do not treat these pilot rules as a validated SPI fitting method.

### Independent numerical checks

After building the temperature pilot, run:

```r
source("scripts/check-prism-monthly-temperature-pilot.R")
monthly_temperature_check$summary
monthly_temperature_check$samples
subset(monthly_temperature_check$comparisons, status == "FAIL")
```

This uses eight PRISM grid locations near Phoenix, Tucson, Flagstaff, Yuma,
Albuquerque, Santa Fe, Las Cruces, and the southern Colorado mountains. It
samples modeled grid cells, not station observations. The latest ending month
comes from the saved pilot summary; the historical contrast uses the same
ending month in 1993. Historical ranking comparisons stop at 1993, and normal
departures are withheld when fewer than 27 matching 1991-2020 years exist.

An independent calculation maps each monthly mean onto every actual calendar
day and averages those daily values. Base-R average ranks provide a separate
check on percentile and rank direction. Every eligible reference window is
compared with production day-weighted arithmetic, and eight latest-period
metrics are checked against the actual saved GeoTIFF values. The historical
comparison checks scalar production rules; it does not build a historical map.
The independent base ranks round to eight decimal places to avoid floating-point
noise; any difference at a production tie boundary is reported for investigation.

The check verifies input checksums and their saved audit signatures before using
the pilot. If inputs changed since the build, rebuild the pilot first. Point
inputs are cached separately, with checksum and location-based invalidation.
Reports in `data/diagnostics/prism-monthly-temperature-check/` include a summary,
metric comparisons, reference-window comparisons, readable location samples,
grid-cell coordinates, and methods. A FAIL stops the review script after
saving reports. Latest-metric tolerance is 0.0001 (allowing Float32 GeoTIFF
rounding); reference-window mean tolerance is 1e-8 F.

This is independent verification of arithmetic using the same local PRISM
inputs. It is not an independent observational validation of PRISM. No network
requests, input changes, map generation or publication occur.

**November 7, 2026 result:** PASS for October 2026 and October 1993 at all eight
locations: 128 metric comparisons and 1,832 reference-window comparisons,
zero failures, 102.27 seconds on the first point-input extraction. October
2026's 12-month mean ranked warmest among 131 windows at these sampled grid
cells. The 1993 contrast ranged from approximately the 6th to the 95th
percentile among 98 then-available windows. This supports the arithmetic and
shows that historical comparisons are not mechanically stuck in the top class;
it is not an external confirmation of the modeled record warmth.

### Multi-period temperature and precipitation ranking review

To build the full local review set, run from the project root in RStudio:

```r
source("scripts/run-prism-monthly-ranking-pilots.R")
monthly_ranking_pilots$summary
monthly_ranking_pilots$results
browseURL(normalizePath(monthly_ranking_pilots$gallery))
```

This builds **eight maps**: 1-, 3-, 6-, and 12-month temperature rankings and
precipitation rankings. The previously reviewed 12-month temperature pilot is
preserved; a separate copy is built for this common gallery. For October 2026,
the periods are October, August-October, May-October, and November 2025-October
2026. The first three have up to 132 matching windows ending in 1895-2026;
the 12-month period has 131 ending in 1896-2026.

The batch audits inputs **once** and shares that fresh result across products.
Each completed product has a checksum-verified completion marker. Rerunning
the script skips unchanged completed products; a missing or damaged output or
changed source/support settings requires rebuilding that product. Failures are
recorded per product; the script stops after saving the batch report, so rerun
to resume. Do not run concurrent writers against these pilot folders. Markers
and outputs here are development diagnostics, not operational monthly success
markers or publication state.

Outputs are under `data/diagnostics/prism-monthly-ranking-pilots/`:

- `index.html`: local two-column map gallery, with full-resolution PNG links.
- `summary.csv` and `last-batch.csv`: status, timings, support and errors.
- `YYYY-MM/temperature/01month/` and corresponding duration folders.
- `YYYY-MM/precipitation/01month/` and corresponding duration folders.

Precipitation windows **sum monthly totals**; they are not weighted by month
length. A missing, nonfinite or negative month invalidates that cell's complete
window. Empirical percentile, minimum support, matching ending month, current
year inclusion, and average-tie rules match the temperature framework. Wet rank
1 is wettest; dry rank 1 is driest. Companion grids contain total inches,
1991-2020 mean/departure/support, full-record sample size, and the historical
zero-precipitation fraction. These are **not SPI** maps; no distribution is fit.

Zero-rainfall ties matter especially for short dry-season windows. A zero total
does not automatically mean an exceptional drought; its percentile depends on
the historical distribution. If all valid totals are zero, the percentile is
50 and the map uses the middle class. Precipitation colors run from brown/dry
through a neutral middle to teal/wet. Temperature retains blue/cool through
neutral to red/warm. Both middle classes refer to the full historical record,
not necessarily a zero departure from the 1991-2020 mean.

Optional limited runs, before sourcing the script:

```r
# Only the new temperature periods; omit precipitation for this run.
options(swc.monthly.temperature.durations = c(1L, 3L, 6L),
        swc.monthly.precipitation.durations = integer())
source("scripts/run-prism-monthly-ranking-pilots.R")

# Restore the complete eight-map set for subsequent runs.
options(swc.monthly.temperature.durations = NULL,
        swc.monthly.precipitation.durations = NULL)
```

To force regeneration after a deliberate display change, set
`options(swc.monthly.force.pilots = TRUE)` before running and reset it to
`FALSE` afterward. Normal reruns reuse verified products. A gallery represents
the products requested in its latest successful run. No downloads, daily
updates, site rendering or S3 publishing occur.

### Separate true-record class (November 7)

The monthly ranking maps now have a separate top class: **Record warm** or
**Record wet**, including tied historical maxima. Ordinary values above the
98th percentile remain in a distinct **near-record** class. A percentile alone
does not establish an actual maximum.

Record eligibility requires a usable current window, all eligible matching
historical windows at that cell (not just the 90% support rule), and at least
one lower historical value. Thus a cell with incomplete history can still show
a supported percentile but cannot claim a full-record maximum. All-zero rain
and other constant series are not highlighted as records. Numerical ties use
the same 1e-8 native-unit tolerance as the rankings. The asterisk in the legend
states that records include ties and require the complete comparison set.

`record_high.tif` and `record_high_tied.tif` store the separate flags. The
scientific `percentile.tif` retains its original 0-100 values. The renderer uses
`display_class.tif` with internal category code 101 for records; this is not a
101st percentile. Purple identifies record warmth and dark blue record wetness;
the surrounding percentile classes retain the temperature/rainfall color ramps.
Summaries report record and tied-record cell counts over the padded map domain.
They are grid-cell records within PRISM, not station records.

Rerun the same review script and reopen the gallery:

```r
source("scripts/run-prism-monthly-ranking-pilots.R")
monthly_ranking_pilots$results
browseURL(normalizePath(monthly_ranking_pilots$gallery))
```

The updated completion-policy version rebuilds each product once to calculate
the new flags and map class. No force option or new downloads are needed.
Subsequent unchanged runs reuse the verified outputs.

### Record cold and record dry

Monthly maps now show **Record cold** and **Record dry** as separate low-end
categories. All nine legend classes remain visible even when no current cells
qualify. These minima require all eligible historical windows and at least one
higher value; ties qualify, while constant series do not. Temperature record
cold uses dark navy and precipitation record dry uses dark brown.

For precipitation, a **zero total qualifies for record-dry highlighting only
when zero occurs in at most 2% of valid matching historical windows**, including
the current window. With 131 or 132 complete windows this allows at most two
zero totals. This is an explicit display safeguard, not a fitted drought index
or a change to the underlying percentile calculation. More common zero minima
retain their ordinary percentile category. Positive record-low totals can
qualify normally, including ties. All-zero histories are never marked as records.

`record_low.tif` and `record_low_tied.tif` store eligible minima;
`record_low_zero_withheld.tif` identifies precipitation minima suppressed by
the zero-frequency rule. Summaries count record/tied-record lows separately.
The map footer documents the zero rule. `display_class.tif` uses internal code
**-1 for record lows** and **101 for record highs**; scientific percentiles stay
in 0-100. The maps' <=2 percentile category is now called near-record cold/dry.

Rerun `source("scripts/run-prism-monthly-ranking-pilots.R")` and reopen the
gallery using the commands above. The new completion policy rebuilds maps once
without requiring new downloads or a manual force setting.

### SPI-1, SPI-3, SPI-6 and SPI-12 local pilots

Run from the project root in RStudio:

```r
# Quick independent numerical fitting checks; no climate data downloads.
source("scripts/test-prism-monthly-spi-methods.R")

# Generate or resume all four maps, then open the local gallery.
source("scripts/run-prism-monthly-spi-pilots.R")
monthly_spi_pilots$summary
monthly_spi_pilots$results
browseURL(normalizePath(monthly_spi_pilots$gallery))
```

The method check uses **MASS**, an R recommended package, to independently
optimize gamma fits for several distribution shapes, and checks the mixed-zero
transformation analytically. If MASS is missing, install it with
`install.packages("MASS")` before running. The map builder also runs this quick
method check automatically. It adds no dependencies to daily publishing.

**Pilot calibration choice: fixed 1895-2020.** Fit matching ending-calendar-month
precipitation sums separately for each duration and grid cell. This long fixed
reference provides samples for short-period fitting and avoids changing the
reference distribution whenever another current year arrives. It differs from
the empirical rankings, which include the latest year in the full record, and
from the 1991-2020 normal used for departure maps. This is an explicit pilot
choice to review before production, not a claim that SPI has one universal
required calibration period.

For October targets, SPI-1/3/6 use 126 candidate windows ending in 1895-2020;
SPI-12 uses 125 ending in 1896-2020 because its preceding November-December
inputs are unavailable for a window ending in October 1895. Actual effective
calibration years are printed on each map and listed in `calibration-windows.csv`.
Current values after 2020 never enter parameter fitting. Multi-month totals
require every monthly input at a cell, without missing-month imputation.

**Calculation:** fit a two-parameter gamma distribution to the positive
calibration totals using maximum likelihood. Shape solves
`log(shape) - digamma(shape) = log(mean(x)) - mean(log(x))`; scale is
`mean(x) / shape`. Let `q` be the fraction of nonmissing calibration totals
equal to zero. Transform the mixed cumulative probability
`H(x) = q + (1-q) * pgamma(x, shape, scale)` to `qnorm(H(x))`.
The classic zero convention uses `H(0)=q`. No precipitation z-score or empirical
rank is substituted when a fit fails.

This gamma-to-normal approach follows the
[UCAR SPI description](https://climatedataguide.ucar.edu/climate-data/standardized-precipitation-index-spi)
and [NCL gamma-MLE SPI method](https://www.ncl.ucar.edu/Applications/spi.shtml).
The chosen zero convention is described in the
[climate_indices reference](https://climate-indices.readthedocs.io/en/stable/reference.html).
MLE results need not exactly match products using probability-weighted moments,
Pearson III, different zero conventions or other calibration periods.

**Automatic support and fit guards:**

- At least 50 valid reference years and 90% of eligible calibration windows.
- At least 30 positive reference totals.
- Withhold cells with zero frequency **>=50%**, constant/near-constant positive
  amounts, nonconvergence, or invalid parameters. Common-zero short dry-season
  SPI is difficult to interpret; precipitation percentile maps remain available.
- Withhold positive-distribution empirical-versus-fitted CDF distance **>0.15**.
  This is a conservative pilot quality guard, not a formal KS significance test.
  Save the distance so the decision can be reviewed rather than silently hidden.
- Bound cumulative probabilities to `[1e-10, 1-1e-10]` only for finite numerical
  normal inversion. Flag each affected cell. Do not truncate scientific SPI to
  the map legend range or infer literal return periods from these bounded tails.

Eight display classes use standard thresholds: <=-2 extremely dry, -2 to -1.5
severely dry, -1.5 to -1 moderately dry, between -1 and +1 near normal, +1 to
+1.5 moderately wet, +1.5 to +2 very wet, >=+2 extremely wet, and **gray for not
estimated**. Threshold endpoint behavior is tested. Outside-domain cells remain
uncolored. These SPI categories are not official drought-monitor categories;
SPI does not measure evaporative demand, snow storage or observed streamflow.

**Files and caching:**

- `data/diagnostics/prism-monthly-spi-pilots/index.html`: review gallery.
- Root `method-checks.csv`, `method-policy.json`, `methods.txt`, `summary.csv`,
  and `last-batch.csv`: reproducible method choices and run status.
- `YYYY-MM/01month/` and corresponding duration folders: scientific `spi.tif`,
  precipitation, fitted parameters, reference sample sizes, zero fraction,
  CDF distance, fit/evaluation status, tail-clipping flag, display class,
  `qc-counts.csv`, calibration windows and the PNG. Codes in `display_class.tif`
  are class IDs, not scientific SPI.
- Separate coefficient caches under
  `data/processed/prism-monthly/az-nm-pad050/spi-fits/cal1895-2020/`: ending-month
  and duration-specific RDS fits, calibration windows and verified completion
  markers. Full reference stacks are not retained.

The batch audits inputs once. Unchanged outputs are reused, and a forced map
rebuild can still reuse unchanged calibration coefficients. New current years
outside calibration do not force refitting; changed calibration inputs or
policies do. Failed products retain diagnostic reasons and resume on rerun.
Do not run concurrent writers against the same cache/output folders.

To inspect a map's withheld cells:

```r
read.csv(file.path("data/diagnostics/prism-monthly-spi-pilots",
  monthly_spi_pilots$summary$end_month, "01month", "qc-counts.csv"))
```

For a limited first run, set `options(swc.monthly.spi.durations = 1L)` before
sourcing the script; reset with `options(swc.monthly.spi.durations = NULL)` to
restore all four durations. `options(swc.monthly.force.spi = TRUE)` redraws
products while reusing verified fits; reset it to FALSE afterward.

November 7 real-data smoke check: October 2026 SPI-1 built successfully in
54.97 seconds including the shared cache audit. Of 47,174 currently valid
padded-domain cells, 47,056 received SPI; 117 were withheld for common zeros and
one for the positive-CDF quality guard. No tail probabilities were clipped.
This is a pilot measurement, not a promised full-batch runtime. The remaining
durations await user testing. No downloads, website changes or S3 sync occur.

### Revision-aware monthly updater (local testing)

The updater refreshes the latest eight completed months (normally 24 inputs:
maximum temperature, minimum temperature and precipitation). It also identifies
missing or damaged older inputs for repair. Automatic source checks run only on
days 1–5; `manual = TRUE` permits testing or catch-up outside that window.
One completed refresh per calendar month is recorded, so repeated runs skip it.

All requested inputs are downloaded into a separate staging cache. Before
acceptance, the entire set must pass checksums, grid validation, common geometry
and maximum/minimum temperature consistency. Accepted files are backed up with
a persistent installation journal. A failed installation rolls back; an
interrupted process recovers on the next run. Incomplete downloads leave the
previous accepted cache and maps in place and resume from verified staged files.
Do not delete an unfinished cycle's state or rollback backups.

Changes are detected from grid geometry and numeric values. Metadata-only
differences retain the accepted file. The manifest records refresh timing,
content fingerprints and an age-based provisional/stable expectation; it does
**not** claim that ACIS has confirmed a file as final. The eight-month window
provides a buffer beyond the expected preliminary revision period.

The updater ensures the current temperature rankings, precipitation rankings
and SPI maps at 1, 3, 6 and 12 months. It also rebuilds already-retained dated
products whose inputs changed. Per-product fingerprints distinguish variables
and time windows. Recent revisions do not invalidate SPI's fixed 1895–2020
calibration fits. The first run after this fingerprint change may rebuild all
twelve current products; subsequent runs reuse verified unaffected products.

Run these from the project root in the laptop R console:

```r
# Offline failure/recovery tests, then a read-only preview of the real cache.
source("scripts/test-prism-monthly-update.R")
source("scripts/preview-prism-monthly-update.R")

# November 8 is outside the automatic window, so explicitly allow this test.
source("scripts/load-prism-monthly.R")
monthly_update_result <- run_prism_monthly_update(manual = TRUE)
monthly_update_result$summary
subset(monthly_update_result$changes, changed)
monthly_update_result$products

browseURL(normalizePath(monthly_update_result$ranking_gallery))
browseURL(normalizePath(monthly_update_result$spi_gallery))
```

Install `filelock` with `install.packages("filelock")` if needed. The updater
locks against another revision-updater run. Do not run the older manual monthly
download/map scripts concurrently against these cache and output directories.

The default request cap is 24 per run. If the result is `PENDING_DOWNLOAD`, rerun
the same command to continue. `FAILED` and `PENDING_PRODUCTS` retain progress;
rerun after checking the reported reason. Once inputs have been accepted,
pending maps can resume outside days 1–5 without downloading the inputs again.
After `COMPLETE`, the same command returns `ALREADY_COMPLETE`. To deliberately
repeat source checks in the same completed cycle, use:

```r
monthly_update_result <- run_prism_monthly_update(
  manual = TRUE, refresh_again = TRUE
)
```

The date-aware entry point is `source("scripts/update-prism-monthly.R")`.
Outside days 1–5 it skips new source requests unless manually overridden through
the function. A refresh still incomplete at window end requires a manual resume.
This entry point is **not yet connected to the daily publisher or VM cron**.
No website rendering, S3 sync or publication occurs in these tests.

Latest reports are in `data/diagnostics/prism-monthly-update/`: `summary.csv`,
`downloads.csv`, `changes.csv`, `products.csv` and `rebuild-plan.csv`.
Persistent cycle records are under the monthly cache's
`revision-state/cycles/YYYY-MM/`, including `state.rds`, `download-events.csv`,
`changes.csv`, `rebuild-plan.csv`, `products.csv` and `success-summary.csv`.
Unfinished staged downloads consume temporary space and are released after
acceptance. The two existing local galleries remain the review entry points.

### Monthly Climate page: local staging and publication checks

The Monthly Climate page has temperature-ranking, precipitation-ranking and SPI
tabs, with a shared 1-/3-/6-/12-month selector. Switching tabs preserves the
selected duration. Its methods notes are collapsed initially. All twelve maps
remain available if JavaScript is disabled.

After a completed revision update, preview from the project root in RStudio:

```r
source("scripts/preview-prism-monthly-site.R")
```

This audits the accepted monthly cache, checks each map's completion hashes and
current input/policy fingerprint, copies twelve PNGs into a versioned site
directory, generates `site/pages/monthly-climate.qmd`, renders only that page,
and validates the rendered images and full-resolution links. In an interactive
R session it opens `site/_site/pages/monthly-climate.html` in your browser.
It makes no downloads and performs no S3 sync. Quarto's normal project resource
copying still runs during this single-page render.

For separate staging/rendered validation steps:

```r
source("scripts/stage-prism-monthly-site.R")
# Render through RStudio's Render button or the preview script above, then:
source("scripts/check-prism-monthly-publication.R")
```

Checks report to `data/diagnostics/prism-monthly-publication/{summary,checks}.csv`.
A successful report has `PASS`, twelve maps and zero failed checks. Corrupt,
missing or stale products fail before the staged page is replaced. A release
uses one month and one version folder, so its page cannot mix monthly sets.
Generated PNGs and `manifest.json` are included as Quarto resources. Checks
also reject missing rendered assets or changed checksums after rendering.

Offline tests:

```r
testthat::test_dir("tests/testthat", filter = "^prism-monthly-site$", reporter = "summary")
```

The site now includes the Monthly Climate link above Historic Years and checks
its rendered maps before daily or site-only S3 publication. Follow the
[grouped-map staging release instructions](monthly-and-grouped-maps-staging.md)
to test the retained release on the VM. Automatic monthly calculation hooks
and full cache/fit transfer remain a separate follow-up. Stable external
SPI-12/temperature-rank-12 aliases also remain a separate publication step.

### Remaining development

1. Complete the historical regional cache and audit missing months, geometry,
   cross-variable consistency, storage, and retrieval time.
2. Build complete 1-/3-/6-/12-month windows: precipitation sums and explicitly
   defined day-weighted temperature averages. Develop full-record ranking and
   1991-2020 departure products; verify ties and support before mapping.
3. Validate SPI fitting and fixed reference-period choices, ending-month
   distributions, zeros, fit failures, and minimum historical support. A
   precipitation z-score is not a substitute for SPI.
4. Publish stable SPI-12 and temperature-rank-12 image URLs for Drought and
   Grazing, alongside the selected SW map set. Add SPI/ranks at 24 months next.
5. Integrate a once-monthly operational job: the previous month is expected
   during the first couple days of the current month. Proposed retries are
   days 1-5, configurable after availability testing. Check all required fields
   before accepting the target month, skip subsequent attempts after successful
   completion, retain prior verified maps on failure, and report an unresolved
   update at window end. Include bounded preliminary-month revision checks in
   this same monthly run. Manual catch-up remains possible outside the window.

The early-month policy and resumable success marker are implemented in the local
revision updater above. Production scheduling, staging-site review and stable
external image URLs remain to be integrated. Availability is not guaranteed by
the calendar.

## Offline tests

```r
testthat::test_dir("tests/testthat", filter = "^prism-monthly", reporter = "summary")
```

Tests use small synthetic grids and make no network requests. They verify
calendar guards, monthly request semantics, partial-batch resume, checksum and
request-identity invalidation, and preservation of good grids on bad refreshes.

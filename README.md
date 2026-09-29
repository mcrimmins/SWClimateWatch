# Southwest Climate Watch

A Quarto website for automatically updated climate maps covering Arizona and
New Mexico. Analysis is written in R using PRISM climate data.

To update the climate data and publish the website from the project root in
RStudio, run `source("scripts/daily-update-and-publish.R")`. See the
[publishing guide](docs/publishing.md) for previews, forced publishing, and
site-only options.
The [publishing guide](docs/publishing.md#optional-phone-notifications-with-ntfy)
also explains optional ntfy phone alerts for progress, errors, and success.

## Project layout

```text
site/                    self-contained Quarto source project
site/pages/              public website content
site/maps/generated/     rendered map products (not committed)
site/_site/              rendered static website (not committed)
data/raw/                downloaded source data (not committed)
data/processed/          analysis-ready data (not committed)
R/                       processing and map-generation functions
tests/                   automated R tests
scripts/                 render and deployment entry points
docs/                    technical processing documentation
reference/map-layers/    versioned geographic context used on maps
```

The repository root is the analysis project. The Quarto website is fully
contained under `site/`; processing code, tests, data, and technical workflow
documentation remain outside the website source tree.

## Local build

Install Quarto and the R packages `terra`, `sf`, `ggplot2`, `ggrepel`, `magick`, `dplyr`,
`lubridate`, `maps`, `httr2`, `jsonlite`, `digest`, and `testthat`, then run from the
repository root. Enter the self-contained site project before starting Quarto:

```bash
cd site
quarto preview
```

To run the same update-and-render path intended for automation:

```bash
bash scripts/render-site.sh
```

## Local PRISM downloader development

Run the offline downloader tests from the project root:

```powershell
Rscript tests/testthat.R
```

The live test downloads a two-day PRISM GeoTIFF over a small Arizona bounding
box. It is opt-in so normal test runs do not require network access:

```powershell
$env:SWC_LIVE_TESTS = "true"
Rscript tests/testthat.R
Remove-Item Env:SWC_LIVE_TESTS
```

Creating a bootstrap plan does not download data. For example, this constructs
the complete stable 1981-2025 daily archive plan:

```r
source(file.path("R", "config.R"))
source(file.path("R", "acis-prism.R"))
plan <- plan_prism_download("bootstrap")
```

Routine PRISM updates are also opt-in during development. To run the update and
site-data entry point locally:

```powershell
$env:SWC_UPDATE_PRISM = "true"
Rscript R/update-data.R
Remove-Item Env:SWC_UPDATE_PRISM
```

Leave `SWC_UPDATE_PRISM` unset for ordinary Quarto renders that should not make
network requests.

Update mode intentionally revisits nine PRISM revision ages for each of the
three downloaded variables, so an ordinary run may show as many as 27 small
requests even when no new date is available. Each refreshed GeoTIFF is compared
with its previous checksum. If all downloads are byte-identical, the workflow
skips the archive-wide checksum scan, processing, all 51 product maps, and the
overview map. A sub-second manifest comparison still checks for any raw file
left unprocessed by an interrupted earlier run. Set `SWC_FORCE_MAPS=true` only when
you deliberately need to rebuild maps after a style or configuration change.
It can be combined with `SWC_UPDATE_PRISM=false` for a local map-only rebuild
that makes no RCC-ACIS requests.

After changing the shared map layout, regenerate the current map images from
the project root in the RStudio console before rendering or validating the
site. This makes no PRISM download requests:

```r
Sys.setenv(SWC_UPDATE_PRISM = "false", SWC_FORCE_MAPS = "true")
map_rebuild_time <- system.time(source("R/update-data.R"))
swc_update_result$summary
Sys.unsetenv(c("SWC_UPDATE_PRISM", "SWC_FORCE_MAPS"))
```

The published-map validator now expects 1998 by 1533 pixel PNGs. It will flag
the previous-size images until the map-only rebuild completes. Freeze-season
maps that retain a prior completed season are repainted from their existing
processed grids when the layout is out of date; this does not change their
observation date or reprocess PRISM data. If a map-only rebuild was interrupted
at validation after updating the other maps, the RStudio console can finish
just those retained maps and the site catalog without repeating the full map
rebuild or making any RCC-ACIS requests:

```r
source("scripts/refresh-retained-freeze-layout.R")
refreshed_retained_maps[, c("id", "date", "map_path")]
table(map_status$validation_status)
```

Historic Years
pilot images are generated separately and are not changed by this daily map
workflow.

The last scheduled revisit is 215 days after each observation, providing a
post-six-month check in case PRISM's final daily revision is released after our
184-day check. This is a time-based safeguard, not a confirmation that PRISM
has marked an individual grid final.

Daily stage timings are appended to
`data/diagnostics/daily-update-timings.csv`; detailed product-group timings are
appended to `data/diagnostics/map-update-timings.csv`. Both reports are ignored
by Git. The returned `swc_update_result$summary` reports the numbers downloaded,
changed, and processed, whether maps were rebuilt, the source dates, and total
elapsed time.

Downloads are sequential and conservative by default: at most 100 network
requests per run, with a 1-1.5 second pause between successful requests. The
downloader prints a summary of completed, scheduled, and deferred requests
before starting. Re-running the same bootstrap plan skips download files that
are already present, so a large archive can be built over multiple bounded runs.
Preview the effect of the cap without making a request with
`preview_prism_download(plan)`.

Historical bootstrap requests use calendar-month chunks. Month boundaries keep
files easy to audit, allow individual months to be replaced, and prevent overlap
between successive archive requests.

After the fixed archive is installed, a one-time `catchup` mode downloads
complete intervening months with range requests. Routine `update` mode then uses
small single-day payloads for the current partial month and PRISM revision
dates. Preview both plans before their first run.

The default ACIS area of interest extends 0.5 degrees beyond the Arizona-New
Mexico analysis footprint on every side. Its cache identifier is
`az-nm-pad050`, which prevents older unpadded files from being reused silently.

Raw and processed PRISM rasters retain the native ACIS units: degrees Fahrenheit
for temperature and inches for precipitation. Processing attaches a date to
every layer, gives layers stable variable/date names, validates plausible values,
and records the source checksum so revised raw grids are rebuilt automatically.

Process all downloaded padded daily files from the R console with:

```r
source(file.path("R", "config.R"))
source(file.path("R", "acis-prism.R"))
source(file.path("R", "process-prism.R"))
processing_plan <- plan_prism_daily_processing()
process_prism_daily_plan(processing_plan)
```

The stable archive period and climatology baselines are intentionally separate.
The archive covers 1981-2025; standard normals and percentile thresholds use a
fixed 1991-2020 baseline. Temperature thresholds pool a centered five-day
calendar window and use R quantile type 8. Observed February 29 values are
excluded from fitting and its threshold is interpolated from February 28 and
March 1. Precipitation amount percentiles use wet days of at least 0.04 inch.
Native temperature and precipitation units remain Fahrenheit and inches.
Climatology builds report every 25th completed calendar day and elapsed time.
Daily mean temperature (`tmean`) is derived locally as `(maxt + mint) / 2`, so
it adds no RCC-ACIS requests. Current maximum, minimum, and mean temperature
maps include observed values, departures from the 1991-2020 normal, and exact
percentile ranks from the local five-day baseline. The mean-temperature normal
is derived from the maximum- and minimum-temperature normals; its rank uses
historical daily mean-temperature samples.
The temperature collection also includes 30-day maximum-, minimum-, and
mean-temperature departures. Each averages the latest 30 daily grids and
subtracts the average of the matching 1991-2020 daily normals. The maximum and
minimum maps distinguish sustained afternoon and nighttime conditions, while
the mean map summarizes both.
The public temperature collection also includes 7-, 30-, and 90-day
mean-temperature percentile ranks. Each current rolling average is compared
with seasonally matched rolling averages from 1991-2020 using the centered
five-day ending-date window. The method ranks the multi-day mean itself rather
than averaging daily percentile ranks. Double-precision historical caches are
keyed by duration and calendar day, so routine updates can reuse the local
baseline without rereading the full archive.
The companion extreme warm-day map counts how many of the latest 30 daily
maximum temperatures exceeded their local centered-five-day 1991-2020 90th
percentile thresholds. Both products are calculated locally without additional
RCC-ACIS requests.
The corresponding cold-night map counts the latest 30 minimum temperatures
that fell below their local centered-five-day 1991-2020 10th-percentile
thresholds.
A separate 30-day freeze map counts minimum temperatures at or below 32
degrees F. This absolute-threshold product is retained year-round but is most
informative during the cool-season transition months.
Its companion anomaly subtracts the mean matching 30-day count in a centered
five-day 1991-2020 seasonal window. Historical threshold-count samples are
cached by calendar day so routine updates do not reread the full baseline.
The seasonal first-freeze pair tracks the first minimum temperature at or
below 32 degrees F in each August 1-July 31 season. One map reports the
observed date and the other reports days earlier or later than the median
1991-2020 first-freeze date. The normal is shown only where at least 24 of the
30 baseline seasons recorded a freeze. To avoid publishing an almost-empty
map at the start of autumn, the previous completed season remains online until
September 1 and until at least 5 percent of historically freeze-prone cells
have recorded a freeze in the new season.
The companion last-freeze pair finds the final night at or below 32 degrees F
in the same August 1-July 31 cold season and compares it with the median
1991-2020 last-freeze date. It becomes available on March 1, remains explicitly
provisional while later freezes can still occur, and is final after July 31.
The previous completed season remains online from August through February.
Freeze-free season length is then calculated for each calendar year as the
elapsed days from the last January-July freeze to the first August-December
freeze. Its departure map subtracts the median 1991-2020 length. Negative
values indicate a shorter season and positive values a longer season. Cells
without both freeze bookends remain blank. A new year replaces the completed
map only after September 1 and 5 percent of historically reliable cells have
recorded both dates.

See [PRISM data acquisition and climatology methods](docs/prism-data-methods.md)
for the full rationale, function reference, storage layout, provenance fields,
and RStudio console examples.

See [Map design and branding](docs/map-design.md) for the map hierarchy,
reference layers, footprint behavior, city-label policy, and logo location.

The separate [SNODAS snow-data pilot](docs/snow-data-pilot.md) documents the
sample SWE/depth maps and a capped one-day downloader and processor. Current-
season snow maps now have a separate, quality-gated local site update; the
unified daily publication entry point runs it after the PRISM update. The
[SNODAS availability and quality audit](docs/snodas-availability-audit.md)
documents the provisional historical period, common-grid pilot, resumable
metadata-only directory inventory, bounded SWE/depth content check, and
required safeguards. The October–May WY2005–2025 local bootstrap is complete:
5,103 paired daily grids are processed. Three dates have small, localized
SWE/depth consistency flags; these cells are excluded in memory for future
historical analysis without changing source rasters. Three-date calendar-day
and centered-five-day climatology pilots are complete. The full 244-date
October-May SNODAS reference baseline is also complete. See the
[SNODAS climatology pilot](docs/snodas-climatology-pilot.md) for the method
comparison and the
[resumable October-May baseline guide](docs/snodas-daily-climatology.md)
for methods, local validation, and RStudio console commands.
The [unpublished SNODAS winter map pilot](docs/snodas-map-pilot.md)
compares observed SWE and SWE departure in ordinary and snowier winters.
Categorical classes are the pilot default, continuous maps remain optional,
and a review flag records unusually high modeled SWE without changing the
source grids. A separate [bounded October-May daily updater](docs/snodas-daily-update.md)
refreshes directory listings, downloads at most five listed archives per run,
resumes from verified regional files, and releases full-domain archives after
checking the SWE/depth pair. It allows a brief June closeout for late May
postings. It also stages observed SWE and daily median-departure maps only
when their quality gate passes; the unified script can then render and deploy
the site in the same manually started run. The [end-of-season snow archive pilot](docs/snodas-seasonal-archive.md)
builds peak SWE and snow-covered-day maps from each completed October-May
season for review. Its [read-only snow QC pilots](docs/snodas-seasonal-archive.md#read-only-event-level-qc-pilot)
group high-SWE patches into episodes and screen for strong relative anomalies
below 50 inches. A second-stage, read-only
[relative-anomaly triage](docs/snodas-seasonal-archive.md#relative-anomaly-episode-triage-pilot)
uses daily SWE/depth evidence and groups flagged cells into date episodes
before any publication-rule changes. Its
[local episode review report](docs/snodas-seasonal-archive.md#local-episode-review-report)
shows peak-day neighborhoods and 15-day histories. The 21 historical snow
seasons have been staged locally on the Historic Years pages; site deployment
is a separate step. The [Historic Years snow-map staging guide](docs/snodas-seasonal-archive.md#staging-snow-maps-on-historic-years-pages)
explains the checksum-checked workflow. The [SNODAS remaining-work note](docs/snodas-next-steps.md)
records the manual October 2026 readiness, later unattended-operation work,
and a future seasonal peak-SWE anomaly product.

The expandable website map browser is generated from
`config/map-products.yml`. The catalog contains one stable ID for each of the
51 public products, organized into Temperature and Precipitation branches and
17 topic groups. Set `enabled: false` on a product to skip its public map during
the next data update and omit its generated page and navigation entry. Shared
data prerequisites are still refreshed when another enabled product needs
them. The `scale` field accepts `continuous` or `categorical` and now controls
the actual map renderer. Continuous remains the default; categorical mode uses
grouped, labeled ranges and climate-specific classes for percentiles,
departures, percent-of-normal, freeze timing, and percentile change. Set the
field on an individual product to override the default, for example:

```yaml
pcpn_percentile_30day:
  scale: categorical
  section: Precipitation
  group: Percentile ranks
  label: 30-day percentile rank
  image: prism/precipitation/pcpn-percentile-rank-30day-latest.png
```

Percentile-based products are categorical by default; raw values, departures,
counts, precipitation totals, and other products remain continuous unless
overridden. The selected mode takes effect the next time the data/map update
runs.

The same configuration contains an ordered `dashboard.products` list of four
to six enabled product IDs. It generates the homepage's responsive Current
Conditions card grid. The default six cards show 7- and 30-day mean-temperature
ranks, 30- and 90-day precipitation ranks, current dry-spell rank, and
water-year precipitation rank. Changing this list changes the homepage without
editing Quarto markup. Rebuild the homepage, catalog pages, and navigation from
the R console with:

```r
source(file.path("R", "map-product-site.R"))
build_map_product_site()
```

`scripts/render-site.sh` regenerates the dashboard and catalog-driven pages
before rendering Quarto.

The Historic Years archive is separate from daily updates. It produces eight
maps per water year: six cool-season maps and two full-water-year maps. The
initial WY1998 and WY2011 pilot can now be expanded in resumable batches;
the first recommended batch is WY1982-WY1986. The fixed 1982-2025 ranking
reference, 1991-2020 temperature normals, dated NOAA CPC RONI snapshot,
output locations, and RStudio build commands are documented in
[the seasonal archive methods](docs/seasonal-archive.md).

Before publication, `scripts/validate-map-products.R` verifies every enabled
current-map PNG, its dated source copy and data date, generated page, navigation
entry, and full-resolution link. It also checks all 44 Historic Years pages and
352 archive PNGs, including their RONI badges, navigation, rendered links, and
copies in the rendered site. The archive uses the current 1998 × 1533 map layout;
the two original pilot years, WY1998 and WY2011, are explicitly accepted in
their older 2070 × 1472 layout and counted separately. Seasonal freeze products
may retain their most recent publishable completed-season maps. The checks write
`data/diagnostics/map-product-status.csv` and
`data/diagnostics/archive-publication-status.csv`, and stop the workflow if
anything required fails. From the RStudio Terminal, validate an already
rendered site with:

```powershell
Rscript scripts/validate-map-products.R --require-rendered
```

See [PRISM map product workplan](docs/map-product-workplan.md) for completed
products, the next implementation phases, deferred products, and the scientific
rationale for the public map collection.

Historical rolling-precipitation samples are cached by duration and ending
calendar day. Repeated map updates reuse a cache when its processed-source
signature is unchanged. A normal next-day cache is advanced from its validated
previous-day parent by subtracting the outgoing daily grids and adding the
incoming daily grids. The same exact update is used for the 7-, 30-, and 90-day
mean-temperature reference samples. Parent checksums and source signatures are
recorded, and missing, stale, or February 29 parents fall back to a direct
build.
Historical water-year-to-date samples use water years 1991-2020 (October 1,
1990 through September 30, 2020). They reset on October 1 and can be advanced
from a validated previous-day cache by reading only the newly required daily
layers. Cache files use 64-bit values, source signatures, checksums, and parent
provenance. February 29 uses an explicitly labeled interpolation of February 28
and March 1 cumulative reference totals.

The current-conditions page includes water-year precipitation total, percent of
normal, and percentile-rank maps. Percent of normal is suppressed where the
matching historical mean is below 0.10 inch; this avoids misleading ratios to
near-zero precipitation while preserving the total and percentile products.
The rolling collection includes 1-, 7-, 30-, and 90-day totals; 7-, 30-, and
90-day percentile ranks; and 30- and 90-day percent-of-normal maps.
It also maps the 14-day change in the 30-day precipitation percentile rank;
positive values indicate recent wetting and negative values recent drying.
Dry-spell monitoring counts consecutive days below the 0.04-inch wet-day
threshold and ranks the current length against a centered five-day 1991-2020
seasonal sample. Its adaptive historical lookback prevents one-year truncation,
and subsequent calendar-day caches update incrementally from validated parents.
The companion longest-dry-spell product finds the maximum uninterrupted dry
run in the trailing 180 days and ranks it against seasonally matched historical
180-day windows. A moving window is used instead of a water-year maximum so the
normally dry Southwest spring does not remain embedded in the product for the
rest of the water year. Its exact historical calculation groups the five nearby
ending dates for each baseline year into one raster pass, reducing repeated
archive reads without changing the statistic.
Wet-day-frequency monitoring counts days with at least 0.04 inch during the
latest 90 days and ranks that count against matching centered five-day
1991-2020 samples. Its cache also advances one calendar day by dropping the
outgoing wet/dry indicator and adding the incoming indicator. A tiny numerical
tolerance preserves the intended classification of 0.04-inch values stored in
float rasters; it does not change the published threshold.
Wet-day intensity averages precipitation amounts from those qualifying wet
days over the latest 90 days; sub-threshold amounts are excluded and cells with
no wet days are omitted. Its companion percentile compares against seasonally
matched 1991-2020 windows, distinguishing event intensity from wet-day
frequency. For the operational one-wet-day minimum, a validated next-day cache
updates its wet-day sum and count from the two boundary days; other minimum
counts use the direct method.
Very-wet-day contribution reports the percentage of the latest 90-day total
supplied by days strictly above the local 1991-2020 wet-day p95 threshold.
Unlike wet-day intensity, it measures the dominance of climatologically large
events in the total. Cells with less than 0.10 inch are omitted, and a companion
percentile ranks the contribution against seasonally matched 1991-2020
windows. Its next-day cache advances the threshold-qualified numerator and the
total from validated parents, with a direct rebuild whenever validation fails.
The water-year extreme-event product maps the largest complete rolling
three-day precipitation total observed since October 1. Its percentile compares
that maximum-so-far with maxima from complete water years 1991-2020, so the
rank is labeled provisional until the active water year ends. The fixed
30-layer historical cache is reused across daily updates.
The companion precipitation-concentration map reports the percentage of the
water-year total supplied by that wettest three-day period. Cells with less
than 0.10 inch of water-year precipitation are masked to avoid unstable ratios.

After initial validation, build the historical archive in bounded local batches
with one command:

```r
source(file.path("R", "prism-workflow.R"))
batch <- run_prism_bootstrap_batch(max_requests = 25)
batch$status
```

Each call downloads at most the requested number of monthly files, processes all
new raw files, and reports remaining download and processing counts. Repeating
the command resumes from the manifests and existing files.

## S3 deployment

For the **daily local update and publication**, run this single command from
the project root in the RStudio console:

```r
source("scripts/daily-update-and-publish.R")
```

This is a **live** workflow. It checks PRISM and in-season SNODAS, rebuilds
current maps as needed, and renders and validates the site before syncing to
`s3://cales-climate-reports/climate/watch/`. Remote deletion is off. See the
[publishing guide](docs/publishing.md) for all one-line options, including a
dry run and a site-only deployment that does not check for new climate data.

The existing Bash scripts below are for the later Ubuntu automation setup, not
the local Windows workflow:

```bash
export S3_BUCKET="example-bucket"
export S3_PREFIX="optional/path"
bash scripts/update-and-deploy.sh
```

A cron job on Ubuntu can invoke `bash /absolute/path/scripts/update-and-deploy.sh`
and send output to an external log. The scripts resolve the project root from
their own location, so they do not depend on cron's working directory.

# Southwest Climate Watch

A Quarto website for automatically updated climate maps covering Arizona and
New Mexico. Analysis is written in R using PRISM climate data.

## Project layout

```text
data/raw/          downloaded source data (not committed)
data/processed/    analysis-ready data (not committed)
R/                 shared configuration, functions, and update entry point
maps/generated/    rendered map products (not committed)
pages/             Quarto content pages
scripts/           Ubuntu render and deployment entry points
_site/             rendered static website (not committed)
```

## Local build

Install Quarto and the R packages `terra`, `sf`, `ggplot2`, `dplyr`,
`lubridate`, `maps`, `httr2`, `jsonlite`, `digest`, and `testthat`, then run from the
repository root:

```bash
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
Current `maxt` and `mint` percentile ranks can be calculated on demand from the
local five-day baseline without making another API request.

See [PRISM data acquisition and climatology methods](docs/prism-data-methods.md)
for the full rationale, function reference, storage layout, provenance fields,
and RStudio console examples.

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

The deployment script requires the AWS CLI and credentials supplied by the
runtime environment. It does not store credentials in this repository.

```bash
export S3_BUCKET="example-bucket"
export S3_PREFIX="optional/path"
bash scripts/update-and-deploy.sh
```

A cron job on Ubuntu can invoke `bash /absolute/path/scripts/update-and-deploy.sh`
and send output to an external log. The scripts resolve the project root from
their own location, so they do not depend on cron's working directory.

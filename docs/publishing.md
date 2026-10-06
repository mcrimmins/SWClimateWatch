# Updating and publishing the site

Run these commands in the RStudio Console from the **SWClimateWatch project
root**. For the normal daily update and deployment, use this one line:

```r
source("scripts/daily-update-and-publish.R")
```

It checks PRISM for new or revised data, updates the current maps when needed,
checks SNODAS during October-May and the June closeout, refreshes the beta
station explorer from RCC-ACIS, then renders, validates, and syncs changed site
content to the live website. The destination is
`s3://cales-climate-reports/climate/watch/` in `us-west-2`. No remote files are
deleted. It is safe to rerun: existing downloads and processed data are reused,
and the site sync is skipped if its source content has not changed since the
last successful daily publication. This is a manual command, not a scheduler.

## Which command should I use?

| Purpose | RStudio Console command | Changes the live site? |
| --- | --- | --- |
| Normal daily update and publish | `source("scripts/daily-update-and-publish.R")` | Yes, if site content changed |
| Preview the entire daily workflow, including the proposed S3 sync | `source("scripts/load-daily-publish.R"); run_swc_daily_publish(dry_run = TRUE, force_publish = TRUE)` | No |
| Update data and republish even when the site fingerprint is unchanged | `source("scripts/load-daily-publish.R"); run_swc_daily_publish(dry_run = FALSE, force_publish = TRUE)` | Yes |
| Publish existing local data/site changes without checking for new PRISM, SNODAS, or station data | `source("scripts/publish-site-s3.R")` | Yes |
| Preview a site-only render and S3 sync | `source("scripts/deploy-site-s3.R"); deploy_swc_site("s3://cales-climate-reports/climate/watch/", dry_run = TRUE)` | No |

**Important:** The full-workflow preview still downloads/checks live data and
may regenerate local maps. `dry_run = TRUE` prevents only the S3 upload. Use the
site-only preview if you do not want a climate-data update. The site-only
commands build the map catalog and render the site from existing maps; they do
**not** regenerate map PNGs after a change to map-drawing code. For that, run
the [local map-only rebuild](../README.md#local-prism-downloader-development)
first, then use the site-only publish command.

The station beta requires a verified local snapshot in `site/stations/` before
the first render. On a machine where you have already built the screened local
station explorer, stage it without new requests with
`source("scripts/stage-station-beta.R")`. That snapshot is generated locally and
is not committed to Git. A failed daily station refresh keeps the last verified
snapshot; the other map updates can continue. Publication stops if the rendered
station page or its assets are missing. Individual delayed stations remain marked
in the beta page rather than silently treated as current.

The site-only publisher does not update the daily workflow's success marker, so
the next normal daily run may sync the same site again. All commands require
Quarto and a configured AWS CLI with write access to the bucket; credentials
are not stored in this repository. A failed render or validation stops the
sync. The daily workflow validates both the Current Snow and Station Conditions
pages before syncing.

## Preparing a separate production machine

The laptop remains the development environment. Do not schedule the VM or let
it write to the live prefix until it has completed a staging run from a tested
Git commit. The daily publisher normally uses the existing live destination,
`s3://cales-climate-reports/climate/watch/`. Set `SWC_S3_DESTINATION` to an
**explicit dedicated staging prefix** on the VM during testing; for example,
`s3://cales-climate-reports/climate/watch-staging/`. The same setting applies
to the site-only publisher. The destination is validated before the daily
workflow starts, and staging has its own last-success marker, so a staging
sync cannot make the live run appear already published. The S3 sync still does
not delete remote objects. Unset `SWC_S3_DESTINATION` to restore the confirmed
live default. Keep the staging value in the VM's service environment, not in
tracked source files.

Run `Rscript scripts/check-production-readiness.R` from the project root on
both machines before the first VM update. This is a read-only check of code,
R packages, Quarto, AWS CLI, and the principal data and site assets. It prints
the resolved S3 destination and time zone. It does **not** make network
requests, verify IAM permissions, check free disk or RAM, compare versions,
validate every manifest checksum, or prove that Linux maps look identical.
Set the VM's `TZ=America/Phoenix` before scheduling so `Sys.Date()` has the
intended Arizona date.

### One-time transfer checklist

- [ ] Select and record a tested Git commit. Clone that commit on the VM;
  do not run daily production from an automatically advancing `main` branch.
- [ ] Install R, the packages listed by the preflight, a C++ compiler for the
  Rcpp dry-spell calculation, Quarto, AWS CLI, and the geospatial/ImageMagick
  system libraries needed by `terra`, `sf`, and `magick`.
- [ ] Transfer `data/raw/prism/` **with its manifest** and all of
  `data/processed/`. Their relative paths in the manifests must remain
  unchanged. Transfer `data/diagnostics/` as well: it contains station-network
  selection, update inventories, pending-work markers, and publication state.
- [ ] Transfer `site/maps/generated/` and `site/stations/`; both are ignored by
  Git but needed to render the existing current/historic maps and station page.
  The regional SNODAS grids are in `data/processed/snodas/`; the retained
  full-domain `data/raw/snodas/` archives are optional for routine publishing
  and may be kept separately for research audits.
- [ ] Do **not** transfer `site/_site/`, Quarto caches, `.Rhistory`, `.RData`,
  `.Renviron`, AWS credentials, or other laptop-specific secrets. Rendered
  output should be produced afresh on the VM. Use a private transfer location,
  not the public website prefix.
- [ ] Compare file counts and checksums for the transferred manifests and a
  sample of large grids, run the read-only preflight, then render/validate and
  preview the S3 sync. Check the VM's free disk and peak memory separately.
- [ ] Run at least several daily cycles against staging, comparing map dates,
  image appearance, station counts, validation results, and total run time with
  the laptop. Only then switch the VM destination to the live prefix and make
  it the sole routine writer. Keep laptop publishing for manual recovery.

The laptop inventory on October 2, 2026 was approximately 10.4 GiB under
`data/raw/`, 9.0 GiB under `data/processed/`, 0.1 GiB under
`data/diagnostics/`, and 0.7 GiB under `site/maps/generated/`. These sizes
will change as updates accumulate; allow substantial space for temporary
downloads, rendering, and future seasons. `site/_site/` was about 0.4 GiB but
does not need to be copied. Before making a VM release procedure, account for
daily updates to some tracked `.qmd` pages: a plain `git pull` in a running
checkout could conflict with generated changes. Use a controlled release and
data-persistence plan rather than resetting the working tree.
The raw PRISM manifest also contains one old empty-AOI entry for January 2020
maximum temperature that points to a former path; the current AOI-named file
is present. Do not mistake that pre-existing legacy row for a transfer loss.

## Checking the result

The normal daily command prints a final status. In the same RStudio session,
you can inspect it with:

```r
swc_daily_publish_result$status
```

`PUBLISHED` means the live sync succeeded; `SKIPPED_UNCHANGED` means no sync
was needed. A full-workflow dry run returns `PREVIEW`. The daily workflow logs
attempts in `data/diagnostics/daily-publish/runs.csv` and writes the last
successful live site fingerprint to
`data/diagnostics/daily-publish/last-success.csv`. These are local diagnostics,
not files uploaded to the website. Station refresh attempts and provisional
counts are recorded separately in
`data/diagnostics/acis-stations/beta-update-runs.csv`.

The site-only command returns `swc_publish_result` in the RStudio session. It
does not update the climate data or the daily publication log.

## Optional phone notifications with ntfy

Install the ntfy app on your phone and subscribe to a topic. To enable alerts,
set the same topic in your **local R environment**, not in this repository:

```r
Sys.setenv(SWC_NTFY_TOPIC = "YOUR_LONG_RANDOM_TOPIC")
source("scripts/load-daily-publish.R")
swc_ntfy_notify("test", "Southwest Climate Watch test notification")
```

The topic setting lasts for the current R session. For future RStudio sessions,
put `SWC_NTFY_TOPIC=YOUR_LONG_RANDOM_TOPIC` in your user-level `~/.Renviron`
and restart RStudio. The project also ignores a local `.Renviron` file, but
the user-level file keeps this setting out of the project entirely. The
default server is `https://ntfy.sh`. For a different HTTPS ntfy server, set
`SWC_NTFY_SERVER`; if that server requires authentication, also set
`SWC_NTFY_TOKEN` to a publish-capable access token. Do not share or commit the
topic or token.

Live daily runs then send a start notice, PRISM/data-check milestones, a
publishing notice, and a final success or failure notice. A SNODAS failure or
quality hold sends a warning while the last verified snow page remains in
place. A station refresh failure also sends a warning while the last verified
station page remains in place. The site-only live publishing command sends start, publishing, success,
or failure notices too. Dry runs send **no** phone alerts. Alert messages are
deliberately high-level. The final daily notice and console summary include total
wall time, PRISM request/change/processing counts, whether maps were rebuilt,
snow and station status, and current/historic map pass counts when the site was
rendered. The site-only final notice includes wall time and map pass counts.
An unchanged-site run skips rendering and therefore does not repeat old
validation counts. Older-layout pilot maps are tracked in the detailed
archive validation report but omitted from routine phone notices because they
do not change the outcome of a daily run. Consult the local console and
`data/diagnostics/daily-publish/runs.csv` for the underlying error or exact
elapsed seconds. A failed ntfy delivery warns locally but does not stop
the update or deployment. An abrupt computer shutdown cannot send a final
failure alert.

On `ntfy.sh`, topics are publicly subscribable unless access control is
configured, so choose a long, unguessable topic and avoid putting private
details in notification messages. See the official [ntfy publishing and topic
guidance](https://docs.ntfy.sh/publish/).

For low-level deployment settings such as a different destination or an
explicit deletion preview, use `deploy_swc_site()` in
[`scripts/deploy-site-s3.R`](../scripts/deploy-site-s3.R). Keep `delete = FALSE`
for routine publishing.

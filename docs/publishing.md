# Updating and publishing the site

## PRISM freshness and automatic fallback

Normal daily publication now tries yesterday after completing the usual PRISM
revision/gap queue. All three fields must validate together; otherwise it keeps
the completed two-day-old set (or an already verified yesterday set). This is
automatic and does not require a new daily command. Console and ntfy completion
messages include the selected PRISM date and availability outcome. Detailed
reasons are in `data/diagnostics/prism-availability/update-status.csv`.

For a small staging test that does not render or sync the site:

```bash
TZ=America/Phoenix Rscript scripts/test-prism-latest-fallback.R
```

This tests simulated fallback and live availability using temporary grids. A
live `FALLBACK` is expected if yesterday has not yet arrived; it is not itself a
test failure. See [PRISM methods](prism-data-methods.md#opportunistic-one-day-operational-lag).
To disable optional yesterday requests, set `SWC_PRISM_TRY_YESTERDAY=false` in
the applicable VM environment file. Revision/gap requests retain their existing
failure policy; this fallback applies to the optional newest date.

## Optional weather maps

Optional Weather maps now have an opt-in daily adapter and a retained,
resumable archive. They remain disabled by default until their staging trial
passes. See [weather daily workflow](weather-circulation-daily-workflow.md) for
bounded local tests, backfill and the staging-only enable setting.

After publishing the weather-enabled staging release, run
`Rscript scripts/check-weather-publication.R` on the VM (or source that script
in RStudio). It checks local staged/rendered activation, files and coverage
without downloading data or publishing. Daily and site-only publishers also
save the report automatically during rendered-weather validation; see the
weather workflow document for report fields and PASS/WARN/FAIL meanings.

## Home dashboard refresh (local review)

The hydroclimate-oriented home layout reuses six existing maps: seven-day rain
total, 30- and 90-day precipitation percentiles, water-year precipitation
percentile, 30-day mean-temperature departure and current dry-spell percentile.
Tool links lead to Daily Explorer, Station Conditions, Current Snow and recent
historic years. The generator in `R/map-product-site.R` owns the page; changing
only `site/index.qmd` would be overwritten by the next catalog build.
The title has a compact status card with the rendered snapshot time in Phoenix
time (MST) and the PRISM data-through date. `site/filters/dashboard-status.lua`
stamps the time during Quarto rendering, not in the visitor's browser or the
generated source. This avoids forcing a publication merely because a source
build ran at a different wall-clock time. A failed publication leaves the
previous public snapshot and its timestamp intact.

`config/map-products.yml` controls the products and conditional snow setting.
During October-May, SWE percent of median can replace dry-spell rank only if
the snow image/page match their publication hashes, the date is in the current
water year and no more than three days old, and the verified daily reference
contains at least 1,000 cells with median SWE >=1 inch and >=18 reference years.
This configurable cell-count threshold is a home-page presentation rule, not
a new snow quality-control criterion. Sparse-reference, stale, missing or
unverified snow keeps the dry-spell map. The snow card carries its own data
date and WY2005-WY2025 reference; the page does not apply PRISM's baseline to it.

Build a local layout preview without downloads or map regeneration:

```r
source("scripts/preview-home-dashboard.R")
```

Render `data/diagnostics/home-dashboard-preview` with Quarto and serve its
`_site/` directory. The main preview uses current cached laptop maps; a separate,
clearly labeled historical snow-card example is available when the existing
winter pilot PNG is present. Preview detail links lead to existing public
pages. Production source keeps relative Quarto links. This script updates the
generated local `site/index.qmd` but never publishes or changes the snow files.

After visual approval, this can use the normal laptop commit/push and pinned
VM staging checkout, followed by site-only publication. No new climate maps,
download cadence or weather-renderer signatures are introduced. Check the
staging home page, tool links, historic-year links and conditional panel before
the next daily staging trial. The proposed cumulative-precipitation evolution
chart remains a separate implementation/benchmarking step.

Run these commands in the RStudio Console from the **SWClimateWatch project
root**. For the normal daily update and deployment, use this one line:

```r
source("scripts/daily-update-and-publish.R")
```

It checks PRISM for new or revised data, updates the current maps when needed,
checks SNODAS during October-May and the June closeout, refreshes the
station explorer from RCC-ACIS, stages the current water year plus the preceding
September of cached PRISM data for
Daily Explorer, then renders, validates, and syncs changed site
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
commands build the map catalog, refresh Daily Explorer from cached grids,
and render the site from existing maps; they do
**not** regenerate map PNGs after a change to map-drawing code. For that, run
the [local map-only rebuild](../README.md#local-prism-downloader-development)
first, then use the site-only publish command.

The station page requires a verified local snapshot in `site/stations/` before
the first render. On a machine where you have already built the screened local
station explorer, stage it without new requests with
`source("scripts/stage-station-beta.R")`. That snapshot is generated locally and
is not committed to Git. A failed daily station refresh keeps the last verified
snapshot; the other map updates can continue. Publication stops if the rendered
station page or its assets are missing. Individual delayed stations remain marked
on the station page rather than silently treated as current.

The site-only publisher does not update the daily workflow's success marker, so
the next normal daily run may sync the same site again. All commands require
Quarto and a configured AWS CLI with write access to the bucket; credentials
are not stored in this repository. A failed render or validation stops the
sync. The daily workflow validates Current Snow, Station Conditions and
Daily Explorer before syncing. Daily Explorer is also validated by the generic
site-only deploy function, including when `render = FALSE`.
Current Snow checks observed SWE, absolute departure and percent-of-median
images and their full-resolution links. Seven-day change is checked when
available; otherwise the rendered page must retain the explicit unavailable
notice. Latest map dates and exact seven-day endpoints must match the source.
The new snow comparisons require no additional daily downloads or baseline
builds; unchanged images are reused after checksum verification.

For local preparation with no network access or upload, use
`source("scripts/stage-daily-explorer.R")`. The first build covers the current
water year to date plus the preceding September. Subsequent runs retain earlier
days, reuse unchanged dates, and rebuild revised inputs. A full leap water year
plus September contains up to 396 dates (2,772 maps when all inputs are available).
The console and ntfy daily summary report dates rebuilt/reused. See the
[Daily Explorer release checklist](daily-explorer.md#vm-staging-and-release-checklist)
before deploying this feature to the VM.

## Preparing a separate production machine

For the VM runner, staging schedule, logs, controlled code releases and live
cutover, see [VM daily operations](vm-daily-operations.md). The runner uses an
explicit private destination setting and a shared lock for updates/releases.

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

On the Windows laptop, a checked SCP transfer is available from the project
root in a terminal (where SSH password prompts are visible):

```cmd
Rscript scripts/transfer-production-seed.R
Rscript scripts/transfer-production-seed.R --execute
```

The first command is a local-only preview. The second copies the seven seed
directories one at a time, skips directories whose remote file paths and sizes
already match, and checks each completed directory plus selected MD5 hashes.
It never deletes VM files or publishes the site. An interrupted directory may
need to be copied again; a fully verified directory is skipped on the next
run. The destination defaults to `crimmins@10.222.142.128` and can be changed
with `SWC_VM_SSH_HOST` if the VM's private address changes. Then run the
read-only production readiness check on the VM.

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
## Home RONI and station guidance (October 28, 2026)

The home card uses NOAA CPC's published ERSSTv6 three-month running RONI,
not an average of three seasonal RONI values. The daily update entry point and
`scripts/build-map-product-site.R` check the small source table at most once
per successful check per day and
caches the latest completed period in `data/processed/roni/latest.rds`.
Recent source values can be revised. The card labels warm/neutral/cold index
ranges rather than declaring an ENSO episode from one period. A failed refresh
retains the dated cache with a visible cached-source notice; without a cache,
the card explicitly says unavailable. No maps or historic RONI snapshots change.

For a site-only staging trial after checking out the tested code, refresh the
station HTML from existing summaries before staging it (staging alone copies
the previous HTML):

```bash
Rscript scripts/refresh-acis-station-explorer-preview.R
Rscript scripts/stage-station-beta.R
set -a
source /home/crimmins/.config/swclimatewatch/staging.env
set +a
TZ=America/Phoenix Rscript scripts/publish-site-s3.R
```

The station page's "Reading this preview" disclosure starts closed and opens
using the native keyboard-accessible summary control. A normal full daily run
also rebuilds that HTML from the updated station summaries.

### Per-map home summaries (local Option A trial)

Top quick-link cards are replaced by an Explore more link row near the bottom.
Each map has its own combined AZ/NM summary above the image. Values are
area-weighted using state-boundary cell-center masks, require 98% valid regional
area, and carry the matching input date. Precipitation-total maps can show mean
regional accumulation and the area at/above a configured threshold. Percentile
maps show area strictly below/above configured percentile thresholds, never an
average of pixel percentiles. Temperature-departure maps show regional mean
departure. Dry-spell rank maps show area above a selected rank threshold.

Only existing date-matched accumulation, percentile-rank and temperature
departure grids are read. Their checksums, dates and summary version invalidate
`data/processed/dashboard/regional-summaries.rds`; unchanged inputs reuse it.
Missing inputs display unavailable rather than older values. No downloads or
climatology builds are triggered. Summary colors are visual cues, not drought
classifications or statistical significance tests. Refresh the local trial with
`source("scripts/preview-home-dashboard.R")` or rebuild the full site normally.

Customize `config/map-products.yml` under `dashboard`:

- `products`: selected enabled map IDs, in display order (existing four-to-six limit).
- `groups`: titles and product lists; these must cover the selected maps exactly
  once in the same order. Omit groups for an ungrouped map grid. `snow_title`
  optionally supplies the title when the seasonal snow card is selected.
- `summary_layout`: `per_map` or `none`. Section banners/top summary cards are
  design alternatives, not currently implemented layout modes.
- `summaries`: settings keyed by map ID; `enabled: false` hides one summary.
  Omit an entry to show a map without a summary. `label` changes its period label.
- `metrics`: `regional_mean`, `area_above_threshold`, `area_below_percentile`,
  `area_above_percentile`, as supported by the matching map type. Configure
  `threshold_inches`, `lower_percentile`, and `upper_percentile` where relevant.

The generator rejects unknown/incompatible metrics and invalid thresholds.
Changing map order does not change summary ownership. Supporting a new map type
or calculation requires an R adapter; YAML cannot define arbitrary formulas.
Seasonal snow substitution suppresses the dry-spell summary; the snow card keeps
its own explicit source/date/reference note instead.

Summary text uses short individual chips. Very dry/Very wet mean regional area
below the 10th/above the 90th precipitation percentile by default; hovering exposes the precise configured threshold and
source date. Each tail is colored independently: defaults highlight at 10% area
and use a stronger shade at 25%. Override `highlight_area_percent` and
`strong_area_percent` in a summary's YAML settings (ordered values from 0 to
100). Stronger colors indicate a larger affected area, not greater severity.
These are display thresholds, not tests of regional statistical rarity.
Temperature chips use cool/warm hues beyond +/-0.5 F departure, with stronger
shades at absolute departure >=3 F; no significance claim is made. Raw rainfall
amount/coverage chips remain neutral. Map dates and the shared regional/method
note replace repeated dates and long explanations in every visible chip.

### Headline condition cards (local trial)

`dashboard.headlines` independently controls one to three linked cards, with an
overall `enabled` switch. Each `cards` entry selects an enabled `product`,
`title`, period `label`, and percentile/color thresholds where relevant. Current
defaults are 7-day and 90-day precipitation percentile maps (below P33 / above
P67 area fractions), plus 30-day mean-temperature departure. A headline map
does not have to appear in the six-map grid. Entire cards link to their map's
detail page, with keyboard focus on the title link.

For precipitation, the default color is neutral unless at least 50% of the
region is in one tail; 67% receives stronger shading. If both tails cover at
least 25%, mixed shading takes precedence. Both fractions remain visible in
every available precipitation card. Configure these via `highlight_area_percent`,
`strong_area_percent`, and `mixed_area_percent`. These are presentation rules,
not significance tests. Temperature colors follow the departure cues described
above. Precise P33/P67 cutoffs and color rules are independent of the per-map
P10/P90 Very dry/Very wet chips.

Headline calculations read only cached derived grids and use the same regional
area weighting/98% coverage guard. `headline-summaries.rds` keeps their cache
separate from per-map summaries. Missing data produce a neutral unavailable
card; no date substitution or downloads occur.

### ENSO card magnitude versus official status

The home RONI badge now labels neutral range (absolute index <0.5 C), weak
(0.5 to <1), moderate (1 to <1.5), strong (1.5 to <2), and very strong (>=2),
using El Nino-range wording for positive and La Nina-range for negative values.
These bands describe the latest published three-month index, not an automatic
operational ENSO declaration. Recent RONI estimates remain provisional.

A separate line reports the exact recognized alert category and issue date
from [CPC's ENSO Diagnostic Discussion](https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso_advisory/ensodisc.shtml).
The daily update and site-only catalog entry points check this small source
once per successful daily check, caching it in
`data/processed/roni/enso-status.rds`. Failed/unrecognized/future-dated or older
responses cannot replace the last good status. Cached fallback is labeled;
an issue over 45 days old becomes "Last reported NOAA status" with an age
caution. Missing status remains explicitly unavailable even if RONI is known.

Historic pages retain their existing badges for now. Their next refresh should
apply consistent strength bands to the documented DJF value, with period/source
context and without applying the current operational advisory retrospectively.
This follow-up is recorded in the development roadmap.

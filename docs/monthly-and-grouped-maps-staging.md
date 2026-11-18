# Monthly Climate and grouped Current Maps: staging release

This release adopts the reviewed grouping layout on the site. Only Temperature and Precipitation expand under Current Maps; Snow is a direct
link with Selected map / All maps. All 51 enabled PRISM products are covered by
the grouped pages. No **Original individual pages**
section is published. Existing individual product URLs remain available for
bookmarks and links from elsewhere on the site. Monthly Climate sits immediately
above Historic Years.

## Current Maps navigation (November 8 review)

| Temperature | Precipitation |
| --- | --- |
| Current temperatures | Recent totals |
| Departures from normal | Percentile ranks |
| Daily percentile ranks | Percent of normal |
| 7–90-day mean ranks | Recent precipitation change |
| Temperature extremes | Water-year precipitation |
| Freeze nights | Water-year precipitation extremes |
| Freeze dates and season length | Dry spells |
| | Wet-day characteristics |

The new temperature-extremes and freeze-night pages use tabs for their two
companion maps. Percent of normal offers 30/90-day periods. Recent precipitation
change is a single-map page. Water-year precipitation groups total, percent of
normal and percentile rank; water-year extremes groups the largest three-day
total, event percentile and precipitation concentration.

The event-percentile tab explicitly explains its comparison against **completed**
1991–2020 water-year maxima. Three-day products remain unavailable on October
1–2 even if prior-year PNGs are still on disk. Existing individual URLs continue
to work, but do not clutter navigation. Product descriptions, images and enabled
settings still come from `config/map-products.yml`; presentation combinations and
ordering live in `R/current-map-group-site.R`.

The map catalog generator preserves this navigation on later daily runs. It
honors enabled products and refreshes grouped pages from existing images and
descriptions. The deployment helper stages groups after the other site staging
steps, then checks every grouped map/link, unavailable notice, script and style
checksum after rendering. Monthly Climate's twelve-map release is also validated
before upload. Validation failure stops S3 sync for both daily and site-only
publication.

The SNODAS updater and its existing quality/date validation are unchanged. The
new Snow view reflects the accepted Current Snow source page, including explicit
unavailable comparisons. Its older page URL remains available.

## Laptop review

From the project root in RStudio:

```r
source("scripts/preview-climate-site.R")
```

This stages the current groups, verifies/stages the completed monthly maps,
renders the site and validates both sets. It does not download inputs or upload
anything. To reopen an already rendered site:

```r
browseURL(normalizePath("site/_site/index.html"))
```

Review navigation, all sixteen Current Maps pages and Monthly Climate. Check bookmark
reloads, maximum/mean/minimum, departure periods, Date versus Length freeze
labels, wet-day units and snow's All maps layout. The local snapshot has no
seven-day snow-change image, so that slot has an unavailable notice. The VM can
display its own verified current image when present.

Reports:

Local data limitation noted November 8: the laptop's processed-data manifest is
through November 3, but most current map PNGs remain October 5. Layout/image-link
checks pass; the normal `validate-map-products.R --require-rendered` freshness
check correctly rejects this old local map set. This release does not regenerate
those maps. Use the staging VM's current maps, retain its normal freshness gate,
and do not copy the laptop's current PRISM/SNODAS PNGs over the VM's copies.

- `data/diagnostics/current-map-groups/publication.csv`
- `data/diagnostics/prism-monthly-publication/{summary,checks}.csv`

## Commit before VM checkout

Commit/push the monthly modules, scripts and tests, the grouped-site adapters and
shared preview renderers/assets, generated grouped `.qmd` pages, Monthly Climate
page, site configuration/styles and deployment validation changes together.
Include the applicable documentation and map scales. Do not add local climate
data, rendered HTML, `_site`, unrelated IVT experiments or the stray untracked
filenames. Review `git diff --cached --stat` before committing. Record
`git rev-parse HEAD` after pushing `codex/daily-explorer`.

## VM checkout (staging only)

Run on the VM. This takes the staging lock while changing code; it does not
modify production. If the clean-tree check fails, inspect the remaining changes
before proceeding.

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9
  git stash push -m "Staging generated dates before monthly/grouped maps" -- \
    site/index.qmd site/pages/current-snow.qmd
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/daily-explorer
  git checkout --detach FETCH_HEAD
  git rev-parse HEAD
)
```

Compare the VM hash with the tested laptop commit. For a pinned release, replace
`FETCH_HEAD` with that full hash. No automatic production checkout is included.

## Seed the approved monthly images

The monthly map PNGs are ignored by Git. For this initial **page/layout test**,
copy only the approved monthly publication directory from the laptop. Its dated
release folders include a portable checksum manifest. The committed Monthly
Climate `.qmd` must reference one of these releases. The VM's existing PRISM and
SNODAS current maps supply the other grouped pages; do not overwrite them with
the laptop's older current images.

On the laptop, from the project root in the Windows terminal:

```bat
ssh crimmins@10.222.142.128 "mkdir -p /home/crimmins/RProjects/SWClimateWatch-staging/site/maps/generated/prism"
scp -r site/maps/generated/prism/monthly crimmins@10.222.142.128:/home/crimmins/RProjects/SWClimateWatch-staging/site/maps/generated/prism/
```

Use the working VPN/SSH route for this host. The transferred PNGs are about a
single twelve-map release, not the full monthly input cache. No production
directory is involved.

## Staging site-only publish

On the VM, after checkout and the monthly image transfer:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  set -a
  source /home/crimmins/.config/swclimatewatch/staging.env
  set +a
  test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
  test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
  export TZ=America/Phoenix
  exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
  flock -n 9
  Rscript scripts/publish-site-s3.R
  Rscript scripts/check-current-map-groups.R
  Rscript scripts/check-prism-monthly-publication.R
)
```

This renders and uploads to **watch-staging** using the existing site-only
publication command. It does not download or recalculate the climate maps.
Review the staging site and both validation reports before promotion.

## Separate follow-up: operational monthly updates

The runner hook is now implemented and opt-in with `SWC_MONTHLY_MAPS=true`.
Keep production disabled until the staging integration test is approved. The
staging VM verified 4,746 inputs and four October fits, built twelve maps in
162 seconds, and repeated with `ALREADY_COMPLETE` and zero requests. Follow the
[daily integration guide](monthly-daily-integration.md) for VM checkout,
staging enablement, no-request checks and the real daily-runner test.

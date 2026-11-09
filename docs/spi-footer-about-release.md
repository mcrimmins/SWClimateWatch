# SPI footer and About page update

The SPI footer's "Local pilot" wording was embedded in production PNGs; it was
not stripped during publication. The new display version removes it. The About
page now explains this site's monthly SPI method and links to the WMO guide.
Navigation/page title change to About; `pages/methods.html` remains the URL.

This local review also adds the small sidebar development notice and cleans up
Home → Maps. Its reading notes are collapsed by default, with configured
thresholds and a clear distinction between summary colors and map values.
A compact Historical context bar replaces the five-year archive list and the
duplicated Explore more row; it links to Monthly Climate and the latest
completed water year. The generator preserves this on future daily builds.

To refresh only that footer locally without downloads, new summaries or live
ENSO requests, run `source("scripts/refresh-home-layout.R")`, then render Home.
Include `R/map-product-site.R`, `scripts/refresh-home-layout.R`, `site/index.qmd`,
`site/styles.css` and the Home dashboard tests with the rest of this release.

Scientific fit policy and calibration are unchanged. A product-policy stamp
reopens completed monthly cycles for display refreshes without source requests.
The local test rebuilt four SPI maps, reused eight ranking maps and all four
SPI fits, and staged a new verified twelve-map release. The normal daily
adapter detects this policy change after code promotion, so it need not wait
for the next month's data. For site-only publication, refresh explicitly first.

## Local review and commit

The About and Monthly Climate pages have already been rendered locally. Open:

```r
browseURL(normalizePath("site/_site/pages/methods.html"))
browseURL(normalizePath("site/_site/pages/monthly-climate.html"))
```

To rebuild locally, use `source("scripts/refresh-prism-monthly-display.R")`,
then the existing local preview/render command. Commit/push the three monthly R
module changes, the new refresh script, `_quarto.yml`, the About/Monthly Climate
source pages, tests and documentation. No climate inputs or PNGs belong in Git.

## Staging VM checkout and site-only publication

After pushing the laptop release to `codex/daily-explorer`, run on the VM:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9
  git stash push -m "Generated pages before SPI footer/About patch" -- \
    site/index.qmd site/pages/_synopsis-content.qmd \
    site/pages/current-snow.qmd site/pages/monthly-climate.qmd \
    site/pages/snow-conditions.qmd
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/daily-explorer
  git checkout --detach FETCH_HEAD
  git rev-parse HEAD

  set -a
  source /home/crimmins/.config/swclimatewatch/staging.env
  set +a
  export TZ=America/Phoenix
  test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
  test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"

  Rscript scripts/refresh-prism-monthly-display.R
  Rscript scripts/publish-site-s3.R
  Rscript scripts/check-prism-monthly-publication.R
)
```

Check all four SPI periods, the About navigation/title and the new monthly SPI
section on watch-staging. The refresh should report zero source requests and
reuse existing fits. When approved, pin that same tested commit on production
under its production lock; run the same refresh script before a site-only
publication, using production.env with the exact `climate/watch/` destination.
Alternatively the normal monthly-enabled daily runner performs the refresh.
No cache transfer or new cron entry is needed for this patch.

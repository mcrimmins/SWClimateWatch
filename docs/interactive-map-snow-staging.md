# Interactive Snow: staging test

This release adds the reviewed Snow viewer and local combined-page build. The
manual staging publication opts into a single verified Current Snow snapshot.
It excludes the laptop's historical example and does not enable production or
persist a daily-runner setting.

## Cache transfer

No laptop snow grids, reference caches, winter examples, rendered files or Node
executable need transferring. The VM already uses the required cache to publish
Current Snow: the exact SWE/depth pair, its centered five-day climatology files
and completion marker, plus the exact seven-day-prior SWE/depth pair when
available. A missing/unverified prior endpoint leaves change unavailable; it
does not substitute a date. The existing publication CSV, image hashes, page
hash and source signature must agree before building the viewer.

Use the VM's current cache; the laptop's October and historical examples are
older. If preflight fails, retain its output and resolve the specific stale or
missing Current Snow input with the normal snow workflow before publication.

## Laptop (Windows Command Prompt)

```bat
cd /d C:\Users\Crimmins\RProjects\SWClimateWatch
Rscript scripts/test-interactive-map-snow-pilot.R
git add R/interactive-map-site.R "R/interactive-map-snow-*.R" scripts/interactive-map-assets/index.html scripts/interactive-map-assets/pilot.js scripts/build-interactive-map-snow-pilot.R scripts/build-interactive-map-snow-site-preview.R scripts/preview-interactive-map-snow-pilot.R scripts/test-interactive-map-snow-pilot.R scripts/check-interactive-map-snow-current.R scripts/stage-cached-interactive-map-site.R site/pages/interactive-maps.qmd docs/interactive-map-snow-pilot.md docs/interactive-map-snow-staging.md docs/development-roadmap.md docs/raster-plot-geometry.md tests/interactive-map-snow.cjs tests/testthat/test-interactive-map-snow-site.R tests/testthat/test-interactive-map-snow-current.R
git diff --cached --stat
git diff --cached --check
git commit -m "Add verified Snow snapshots to Interactive Maps for staging"
git push origin codex/daily-explorer
git rev-parse HEAD
```

If Rscript is not on the laptop terminal PATH, run the test by sourcing it in
RStudio, then execute the Git commands in Command Prompt. Generated Home and
synopsis pages, untracked IVT experiments, stray pasted-command filenames, local
data and the Node tools cache are not included. The two existing roadmap/raster
documentation edits record the previously confirmed production release.

## VM (staging checkout and publication)

Run this on virga, not the laptop. It checks out the pushed branch tip and prints
its full hash; compare it with the laptop hash. For a fixed release, replace
`FETCH_HEAD` with that tested full hash.

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e

  set -a
  source /home/crimmins/.config/swclimatewatch/staging.env
  set +a
  export TZ=America/Phoenix
  export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"

  test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
  test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
  exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }

  git stash push -m "Staging generated pages before interactive Snow" -- \
    site/index.qmd site/pages/_synopsis-content.qmd \
    site/pages/current-snow.qmd site/pages/snow-conditions.qmd \
    site/pages/monthly-climate.qmd
  git status --short
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/daily-explorer
  git checkout --detach FETCH_HEAD
  git rev-parse HEAD

  Rscript scripts/check-interactive-map-snow-current.R --preflight
  export SWC_INTERACTIVE_SNOW=true
  Rscript scripts/publish-site-s3.R
  Rscript scripts/check-interactive-map-snow-current.R
)
```

The site-only publisher refreshes the cached PRISM viewer, adds the VM's verified
Snow snapshot under the opt-in, renders, validates all assets and matching Snow
images, and syncs only to staging. It performs no new climate downloads. The
export is scoped to this block; production and the cron configuration are
unchanged. A later daily refresh without the opt-in may replace the Snow view;
automatic persistence is a follow-up after this staging review.

## Review

Open <https://cales.arizona.edu/climate/watch-staging/pages/interactive-maps.html>.

- Choose Current Conditions → Snow → Snowpack water. All four metrics must use
  the same latest verified Snow date, matching the Current Snow page. No
  February 2025 example or local-pilot prose should appear.
- Review transparent zero SWE, positive snowpack, gray low-typical cells, beige
  missing/unsupported comparisons and point-table values. The comparison zeros
  retain their meaning. Check the exact dates for seven-day change, or its
  explicit unavailable notice.
- Switch through Precipitation, Temperature, Daily History and Monthly Climate,
  then return to Snow. Review terrain/satellite, opacity, point queries and the
  full-screen link. Check a small screen as well as desktop.

Expected post-publication check: source and rendered Snow viewer match the VM's
verified Current Snow release. Save the staging commit hash and check output
before enabling automatic Snow refresh or promoting to production.

# PRISM comparison review: assessment and local fixes

November 15, 2026. Assessed the user's independent code-review brief against
the current implementation. Changes are local and not committed, staged on the
VM or published. SNODAS, station calculations, the type-8 percentile function
and the existing C++/R dry-spell algorithms are unchanged.

## Decisions and priority

| Review item | Priority | Decision |
| --- | --- | --- |
| 1. Maximum three-day water-year rank | High: comparison correctness | Corrected to matched water-year-to-date references, with a separate per-calendar-day FLT8S cache and verified previous-day advancement |
| 2. Spring last-freeze departure | High: premature interpretation | Implemented option (a): median date passed and at least 14 days since the latest freeze; gray status for complete observations still in progress; results remain provisional until July 31 |
| 3. Missing overdue first freezes | High: one-sided display | Separate delay lower-bound evidence and purple overdue/no-event class; no invented first-freeze dates or numeric observed departures |
| 4. No-freeze years dropped from medians | High: comparison correctness | Distinguish verified no-event seasons from missing inputs; use censored first/last medians and bounded freeze-free medians; retain 80% event gate |
| 5. Tied zero precipitation ranks | Medium: interpretation | Explain mid-ranks and ties in product descriptions and About; retain the correct rank function and existing classes |
| 6. Freeze categorical boundaries | Low: latent display defect | Shift boundaries by half a day for the existing right-closed cut; normalize display day indexes to a common calendar, including leap seasons |
| 7. Config versus subtitle mismatch | Medium: maintainability/accuracy | Central reference-year/window helpers and configured wet-threshold wording in current builders |
| 8. Sparse wet-day intensity | Optional: estimand/coverage tradeoff | Keep the current minimum of one; disclose volatility and link interpretation to wet-day counts; benchmark 3/5-day alternatives before changing the operational default |

The review correctly identifies items 1–7, but item 4 needs more careful handling
than replacing every NA with infinity. Old caches conflated missing daily data
with complete no-freeze periods. A missing observation must remain unknown.
Also, a missing freeze-free endpoint does not prove the interval exceeds every
finite interval observed at that cell. Blindly assigning infinity can bias its
median upward.

## Cache and comparison semantics

- First- and last-freeze sample caches are now version 2: positive day indexes
  identify events, zero identifies a verified no-freeze season, NA identifies
  incomplete/invalid daily inputs. First medians substitute +Inf for zero only
  while calculating the median; last medians substitute -Inf. Missing baseline
  years withhold the comparison. Frequency rasters remain available, with an
  80% event-frequency gate and a finite-median requirement.
- Freeze-free samples are version 2: positive values are exact lengths,
  negative values encode lower bounds when an endpoint is outside the observed
  year, and NA means missing observations. For missing spring endpoints, the
  last event is at or before day zero; for missing fall endpoints, the next
  event is at or after the day following year end. Compute median lower and
  upper bounds; publish only if both agree on one finite value, with the same
  80% paired-event gate. These bounds need not equal the old conditional median.
- Current first-freeze numeric date/departure grids still contain only observed
  events. `departure-lower-bound` is a separate dated grid and return field;
  only complete current observations can receive an overdue marker. Purple
  is a distinct status, not part of the numeric departure color ramp.
- Last-freeze `season-in-progress` is a separate dated grid. Missing current
  observations or missing/unreliable historical medians do not get painted as
  valid progress. July 31 bypasses the waiting period because the season ends;
  before then, a later freeze can still revise the qualified departure.
- Freeze status cells use exact raster footprints under boundaries/city labels,
  with distinct status legends. Their date plots normalize leap-day display
  indexes only; calculation dates/intervals are not shifted. This is not a
  general replacement of raster drawing throughout the site.
- The completed-water-year maximum cache stays separate and unchanged. Current
  ranks call `build_prism_water_year_maximum_cache(target_date=...)`, using a
  new matched-date versioned path. Reference windows stay inside October 1
  through the matched endpoint. February 29 interpolates February 28/March 1
  maximum-to-date values. February 29 and March 1 build directly; other dates
  can advance from a source-signature/version/checksum-verified predecessor.
  Missing/incompatible predecessors and revised sources trigger direct builds.
- Empirical maximum samples remain FLT8S, use the processed-raster writer and
  manifest conventions, and never zero-fill missing data. The type-8 inversion
  and tie handling are unchanged.

Subtitle helpers read normal/percentile years, centered-window width and wet
cutoff from the configuration. Catalog descriptions remain concise (two
sentences), and the water-year grouped-tab note and About methods now describe
the corrected comparisons.

## Local validation and review

Targeted regressions passed for freeze calculations/caches/statuses, matched
maximum caches, direct versus incremental equality, leap handling, categorical
boundaries, config text, rolling ranks, wet-day products, catalog/grouped pages
and enabled-map dispatch. Simulated rolling three-day maxima retain central
ranks near 50 at early, middle and completed-season endpoints. An end-to-end
processed-grid fixture verifies separate overdue output and missing coverage.

Quick visual review uses explicitly labeled synthetic data; no real maps,
climatology caches or remote files are changed:

```r
source("scripts/review-prism-code-review-fixes.R")
```

It opens `data/diagnostics/prism-code-review/index.html`, with first-/last-freeze
status examples. The PNGs were rendered and visually checked locally.

To refresh the actual local PRISM maps from existing cached inputs:

```r
source("scripts/rebuild-prism-code-review-fixes.R")
```

This is an explicit calculation/migration run, potentially much longer than
the synthetic review. It rebuilds enabled PRISM maps, checks the new cache
versions and recalculates retained completed-season freeze comparisons at their
existing dates. It then refreshes/validates the local product pages. It does
not request PRISM data, run station/SNODAS updates or upload to S3. Missing
cached inputs stop the build instead of triggering a download.

Before staging/production, commit the code, descriptions and tests together and
run this same cached rebuild on staging under its lock. **Do not promote by
repainting old departure rasters or by site-only publication alone:** that
would retain the old comparison values under the new explanatory text. Cache
version 2 causes a one-time freeze-reference rebuild; no first-run timing has
been measured. Review new real-data maps and passing publication checks before
promotion, and repeat the migration on production when promoted.

## Remaining optional work

For intensity, compare 1/3/5 wet-day minimums using the existing parameter,
including reference sample size, display coverage and daily runtime. The fast
incremental intensity path currently relies on the one-day minimum; changing
the default needs either a measured runtime acceptance or retained wet-day
sums/counts, not an unmeasured broad cache rewrite. No intensity cache version
was bumped because its numeric semantics were not changed in this patch.

## Staging release commands

The laptop's completed real-data rebuild was verified on November 15: first,
last and freeze-free reference caches are version 2; the separate matched-date
maximum cache uses version 1, method `matched-water-year-to-date`, and FLT8S.
These are local checks, not a claim that staging or production was updated.

Laptop RStudio (quick migration check):

```r
source("scripts/check-prism-comparison-caches.R")
```

Laptop Windows terminal (CMD), from the project root:

```bat
cd /d C:\Users\Crimmins\RProjects\SWClimateWatch
git add .gitattributes
git add -u R config/map-products.yml
git add scripts/load-prism-review-fixes.R scripts/review-prism-code-review-fixes.R scripts/rebuild-prism-code-review-fixes.R
git add scripts/check-prism-comparison-caches.R scripts/test-prism-comparison-staging.sh
git add docs/prism-code-review-fixes.md docs/prism-data-methods.md docs/development-roadmap.md
git add site/pages/methods.qmd site/pages/dry-spells.qmd site/pages/freeze-monitoring.qmd
git add site/pages/precipitation-ranks.qmd site/pages/water-year-extremes.qmd site/pages/water-year-precipitation.qmd site/pages/wet-days.qmd
git add -u site/pages/products tests/testthat
git add tests/testthat/test-prism-review-freeze-safeguards.R
git diff --cached --stat
git commit -m "Correct PRISM seasonal comparisons and freeze interpretation"
git push origin codex/daily-explorer
git rev-parse HEAD
```

The explicit paths include the changed derived product descriptions but leave
the laptop's generated Home/Synopsis dates, untracked earlier generated pages,
IVT experiments, stray filenames and local data outside this release. Review
the staged list before committing, including anything already staged earlier.

VM staging checkout:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  mkdir -p /home/crimmins/.local/state/swclimatewatch-staging
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9 || { echo 'STOP: another staging job is running.'; exit 1; }
  git stash push -m "Staging generated pages before PRISM comparison fixes" -- site
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/daily-explorer
  git checkout --detach FETCH_HEAD
  git rev-parse HEAD
)
```

Confirm the VM hash matches the laptop. Then run:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
bash scripts/test-prism-comparison-staging.sh
```

This helper validates the staging project/configuration, holds the staging lock,
rebuilds enabled PRISM maps and retained freeze comparisons from the VM's own
cached inputs, checks the migration and only then renders/validates/uploads the
site. It does not run the PRISM downloader, station updater or SNODAS updater.
No image/cache transfer from the laptop is needed. First rebuild timing has
not been measured; allow the full map-generation cycle plus the one-time
freeze reference rebuild. The helper prints progress and elapsed time and logs
to `~/.local/state/swclimatewatch-staging/logs/prism-comparison-*.log`.

Expected cache report: PASS for first freeze (2), last freeze (2), freeze-free
length (2), matched-date maximum (1, FLT8S). The maximum check is seasonally
deferred on October 1–2. Report:
`data/diagnostics/prism-code-review/cache-validation.csv`. Existing rendered
current/historic/monthly/regional/weather/station publication gates still apply.
After staging review, promote this commit and repeat the cache/map migration
on production before its first publication with the new descriptions.

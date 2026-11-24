# Daily Explorer archive navigation and retention pilot

Local PRISM-only review, November 23, 2026. This does not change the live
Explorer, daily cron, site navigation or any S3 objects. No inputs are
downloaded. July's full-month benchmark and weather/report/hazard backfill
remain separate steps.

Local verification passed for four month partitions, 12 sample dates and 84
maps. A second build reused all 12 dates without rebuilding maps. The actual
staging/pruning rehearsal removed seven obsolete current maps and preserved
all completed-year files and the archive catalog. Browser review confirmed
month/year selection, September–October grid navigation, temperature views,
saved date URLs and returning to the latest date, with no console errors.

## Build, validate and preview

From the project root in RStudio:

```r
source("scripts/build-daily-explorer-archive-pilot.R")
source("scripts/test-daily-explorer-archive-pilot.R")
source("scripts/preview-daily-explorer-archive-pilot.R")
```

Preview: `http://127.0.0.1:8799/`. Output is isolated under
`data/diagnostics/daily-explorer-archive-pilot/`. The first build renders seven
maps per sample date and can take several minutes. Later builds reuse each
verified per-date build cache when its inputs/signature match.

Default samples are July 1–7, 2025; September 30–October 2, 2025; and the two
latest locally cached PRISM dates. With the laptop cutoff of November 3,
2026, this is 12 dates and 84 maps across four month partitions and WY2025,
WY2026 and WY2027. These are sample windows, not complete historical months
or water years. Months without built dates are not offered in the selector.

Use Water year and Month above the existing PRISM Explorer controls. Variable,
display, regional summaries, date selection, notable days and 7-/30-day map
grids reuse existing behavior. The selected month determines the single-day
timeline/notable-day scope. Supporting metadata can include neighboring
months for cross-boundary grids. Missing dates remain unavailable; no nearest
date is substituted. A date query in the URL reopens a built selection.

Only the selected month's metadata and needed neighboring month partitions
are fetched; maps load as selected/displayed. The archive index contains
paths and built-date lists, not every day's statistics or event geometry.
Weather and event displays are not enabled in this PRISM-only pilot.

## Retention contract under test

Completed-year files are under `archive/WY<year>/`; updater-owned current-year
files are under `current/`. The root index/catalog and month partitions make
the ownership separation explicit. No existing production paths are migrated.

The test script validates month dates, year assignments, checksums, all seven
map references and versioned assets. In a separate diagnostic sandbox it runs
the **actual** current Explorer staging/pruning adapter twice, first with two
real cached sample dates, then one. Seven obsolete current maps must be
removed, while every copied completed-year file must remain byte-identical.
It uses a bounded builder fixture to replay existing real sample outputs;
it does not rerun climate calculations or publish. JavaScript model checks
cover year rollover, neighboring partitions, unsupported dates, unsafe paths,
duplicate records and missing maps.

This proves the proposed isolated directory ownership for that adapter. Before
production archive integration, the renderer, archive catalog updates, weather
and event adapters, current-year rollover, and full publication validation
must honor the same ownership contract. Do not treat this pilot as an already
enabled production retention policy.

## Review

- Switch among water years and available months; compare precipitation and
  temperature views/summary regions.
- Choose September 30, 2025, switch to a seven-day grid, and choose October 1.
  The water year/month should change together without substituting a date.
- Check 30-day grids: many sample dates are deliberately not built, and gaps
  must stay visibly unavailable.
- Reload a copied date URL and confirm the same map opens.
- Check narrow-window controls and the latest-date button.
- Rebuild and rerun validation to confirm cache reuse and unchanged archive
  bytes. No local preview action uploads anything.

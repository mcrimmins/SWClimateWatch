# Climate of the Region: local page review

November 15, 2026. The local preview does not download data or publish anything.
Cached publication hooks and the portable transfer bundle are now prepared for
the separately requested staging release; the VM has not been changed here.

## Build and preview

Run from the laptop project root in RStudio. The accepted annual, seasonal,
share and daily-reference caches are prerequisites. This stages their verified
outputs and rebuilds the page, without recalculating the 30-year references.

```r
source("scripts/build-climate-of-region-preview.R")
options(swc.climate_region.full_site = FALSE)
source("scripts/preview-climate-of-region.R")
```

Preview: <http://127.0.0.1:8788/pages/climate-of-region.html>. Keep RStudio open.
Let any earlier Quarto render finish first. Even a single-page render copies
site resources; allow time for this. For a full-site render that refreshes the
sidebar everywhere, set `options(swc.climate_region.full_site = TRUE)` first.

To reopen an already rendered page:

```r
source("scripts/serve-climate-of-region-preview.R")
```

## Organization

Three native Quarto tabs:

- **Precipitation:** precipitation total or seasonal share, wet days, amount per
  wet day and heavy-precipitation days.
- **Temperature:** mean temperature, freeze nights and hot days.
- **Seasonal comparison:** four seasons for one selected metric, using a shared
  scale and a two-column grid that stacks on smaller screens.

A shared **Period** selector offers Annual, Winter (Jan-Mar), Spring (Apr-Jun),
Summer (Jul-Sep), Fall (Oct-Dec). It persists between topic tabs. Comparison
always shows all four seasons and disables the period selector while preserving
its selection for returning to a topic.

Precipitation and Temperature each have a **Metric** selector and
**Selected map / All metrics** view. Metric and view selections are remembered
independently per topic. In All metrics, the metric selector is disabled while
its selection is retained. Selected map shows one large image; All metrics
uses a responsive grid.

**Total / Share of annual** applies only to the precipitation-total map. The
control is hidden for other selected precipitation metrics; in All metrics it
changes just the total/share card. Annual always shows Total and disables Share,
while preserving the seasonal preference. Temperature maps do not change.
Comparison includes Share as a separate metric and always shows four supported
seasonal maps. Plot titles are inside images; descriptions and full-resolution
links stay with each map. A single collapsed methods section follows the tabs.

## Products and checks

39 unique PNGs: two annual and eight seasonal monthly references, four seasonal
precipitation shares, and 25 daily-derived annual/seasonal references. Source
files stay in the diagnostic pilot folders; page copies and manifest are under
`site/maps/generated/prism/regional-reference/1991-2020/`. Thresholds, reference
periods, units and complete-period coverage remain as previously reviewed.

The build checks source/output checksums and input inventories, writes the page
and selector script and preserves the sidebar entry below Historic Years and
above About. The page validator checks all declared map copies and download
links, their selector metadata, the three topic panels, control IDs, script,
manifest, navigation and collapsed notes.

```r
testthat::test_dir("tests/testthat", filter="regional-(climate|seasonal|precipitation|daily)", reporter="summary")
```

Control combinations and actual change/tab event wiring:
`node tests/climate-reference-controls.cjs`. The targeted R suite has 99 passing
assertions; JavaScript checks cover every topic/period/metric/view/share
combination, Annual fallback, remembered selections and four-season comparison.

An isolated page-render check avoids copying unrelated station resources:

```r
source("scripts/check-climate-of-region-render.R")
```

Its sidebar targets are not all included, so link warnings for unrelated pages
are expected. It is a verification artifact, not the standard site preview.

Staging preparation is now implemented: cached page staging, rendered validation,
39 stable catalog links and a portable transfer archive. See
[staging instructions](climate-of-region-staging.md). The operational site stays
unchanged until the user runs the staging/promotion commands.

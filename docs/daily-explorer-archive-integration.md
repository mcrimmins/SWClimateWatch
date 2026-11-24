# Full July bundle in archive navigation

Local-only integration, November 24, 2026. Reuses the accepted PRISM archive
samples and full July benchmark. There are no requests, map renders, live-site
changes, cron edits or uploads in this build.

Local checks passed: four month routes/36 dates, with all 31 July dates routed
to the full suite. Browser review confirmed July module loading, the June
2–July 1 thirty-day mean, region/temperature/timing/period restoration, saved
date URLs, no stale event panels in PRISM-only months, September–October year
rollover, and explicit rejection of an unbuilt August date. The browser log
reported no errors during the reviewed flows. User review remains next.

```r
source("scripts/build-daily-explorer-archive-integration.R")
source("scripts/test-daily-explorer-archive-integration.R")
source("scripts/preview-daily-explorer-archive-integration.R")
```

Open `http://127.0.0.1:8801/`. The output is separate:
`data/diagnostics/daily-explorer-archive-integrated/`. The source July viewer
and earlier navigation pilot are validated and left unchanged. Only referenced
PRISM assets are copied; the old seven-date July sample is excluded from the
PRISM child catalog because July now has its complete bundle.

## Organization

- One outer water-year/month/date navigator selects the month viewer. It
  defaults to the latest cached sample date, with an explicit linkable date.
- July 2025 has all 31 dates, 496 maps, 360 reports and 856 hazards. Other
  months retain their five PRISM sample dates and explicitly say the weather
  and event suite has not been built there.
- A month runs in its own same-origin frame. Loading a different month
  replaces that frame, so event/weather caches and controls cannot silently
  keep displaying the prior month's records. Message origin, source and
  navigation-token checks reject stale frame messages.
- Shared region, variable, display and supported period/timing settings are
  carried across month changes. A PRISM-only month does not erase absent
  report/hazard settings. Event type/search filters reset with their month.
- The embedded viewer keeps its existing linked charts, weather selection,
  storm report map/table, hazard map/table and both event timeline rows. The
  outer header replaces duplicate embedded month/year headings. Frame height
  follows content, avoiding a second scrolling panel.
- Parent date links restore the date and supported choices. Exact previous/
  next calendar days are offered only where built; missing months/dates are
  not silently substituted. September 30/October 1 remain a PRISM boundary
  review. July still has the benchmark's complete June-supported weather
  means, while pre-July report/hazard windows and unbuilt neighboring PRISM
  dates retain explicit partial/unavailable notices. No supporting June/August
  map archive or new event backfill is created by this assembly step.

## Validation and review

Validation checks copied release hashes, catalog routes/date ranges, the
remaining PRISM sample partitions, every July map/event/mean, and versioned
browser assets. The build checks that the accepted source index/catalog/release
files remain byte-identical. Tests reject modified copied browser assets and
verify all July dates route to the full suite, samples route to PRISM, and
unbuilt dates have no route. The earlier actual pruning rehearsal remains
separate; production archive retention integration is not enabled here.

Review July in WY2025, then another sample month and return to July. Test
region/temperature settings, daily/7-/30-day weather, both event rows and
timing controls. Confirm no July event counts/maps remain on a PRISM-only
month. Check a saved July date URL, Latest, year rollover, and a narrow window.
The initial page fetches only the catalog and selected viewer; geometry/map
requests follow that viewer's existing lazy-loading behavior.

Cleanup after production archive acceptance is now a roadmap step for the
laptop and both VM projects. No diagnostic/source cleanup is performed here.

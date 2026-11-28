# Daily Explorer Streamflow: local integration

This review adds a collapsed Streamflow section beneath the main map in the
connected current/WY2025/WY2026 Explorer. A "View streamflow" shortcut opens it.
The gauge table is also collapsed by default; the map and selected hydrograph
remain visible together when Streamflow is expanded.
The sticky "Jump to" row below the date controls opens and scrolls to Daily
summary, Main map, Streamflow, Storm reports, NWS hazards, Weather maps,
Discussions and Notable days. Unavailable sections have disabled buttons.
It serves the previously validated archive releases read-only and copies only the
32-gauge snapshot and small UI assets (about 3 MB). It does not download, rebuild
maps, change the site, enable the daily updater or publish anything.

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/build-daily-explorer-streamflow.R")
source("scripts/test-daily-explorer-streamflow.R")
source("scripts/preview-daily-explorer-streamflow.R")
```

Preview: http://127.0.0.1:8807/. Stop a server started by this R session with
`httpuv::stopServer(streamflow_explorer_server)`. The original standalone pilots
remain at ports 8798/8799. If Node is not available in RStudio, set
`options(swc.streamflow.node = "C:/path/to/node.exe")` before testing.

The build requires the existing connected local review and the 32-gauge network
snapshot. If the connected source has changed, refresh it first with
`source("scripts/build-daily-explorer-connected.R")`. Current laptop map inputs
end October 5, 2026; this can be older than production and is clearly labeled.
The available streamflow snapshot covers August 29–November 26, 2026.

## Interaction

- The Explorer date is authoritative. Gauge observations and percentile colors
  are recalculated for that date; later observations are never substituted.
  If a gauge has no observation that day, its latest earlier observation date
  and freshness remain explicit. The chart's selected day still shows a gap.
- Shared single-day, 7-day and 30-day selections drive both the flow chart and
  Map view. Streamflow windows trail the selected date, whereas the existing
  multi-day map tiles retain their original centered browsing behavior.
  Ninety days is a Streamflow-only window. Regional filtering is shared.
- A selected gauge and the open section survive date/month changes when it remains in the region
  and search results. Chart hover updates the adjacent day table without moving
  the Explorer date. Charts support pointer, touch and keyboard day selection.
- The selected-window CSV contains exactly the chart's cached rows, including
  missing/quality fields, and excludes observations after the selected date.
- Dates outside the 90-day snapshot show an explicit unavailable notice.
  Windows extending before its start are labeled partial. Missing values remain
  gaps, and complete seven-day means require all seven numeric daily values.
- USGS daily dates are not shifted into the PRISM precipitation reporting window.
  Historical percentile bands retain their approved-sample support checks.

The Streamflow component loads only after its section is opened. A dated map needs
all 32 compact gauge histories (about 920 KB total), loaded in groups of four and
retained in browser memory. Changing dates then uses those cached histories.
Identical selection messages are suppressed. A small in-memory HTML overlay
inserts Streamflow into the accepted current/archive page without changing its
existing maps, reports or hazards. No source archive files are rewritten.

## Validation and next steps

R checks verify release hashes, 32 identities, 90-day endpoints and safe local
routes. The closed/unloaded section is checked; round-trip byte comparisons of
current/WY2025/WY2026 pages protect all original markup and UTF-8 symbols.
Node checks cover historical-date summaries, missing/zero values,
complete means, date boundaries, no future observations and displayed-window
CSV serialization. Browser review verified shared seven-day controls, date
changes retaining the gauge, unavailable older archives and return to current.

This is an isolated local overlay, not a staged publication bundle. Before
staging: package and validate the integrated static assets with existing cache
versioning, run full connected-archive validation, benchmark on the VM and
review publication checks. Automatic streamflow refresh remains disabled.

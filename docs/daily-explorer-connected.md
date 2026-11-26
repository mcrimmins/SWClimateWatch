# Connected Daily Explorer navigation — local review

The local builder now combines both completed WY2025 and WY2026 releases
with the current cache. The earlier single-year staging trial remains separate;
this addition does not change staging, production or the daily workflow.
Both completed source releases remain read-only. The server routes each year
from its own original directory and adds only small private UI/metadata
overrides, without copying or rebuilding PNGs or geometry bundles.

Restart the R preview server when upgrading from the single-year version:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
if (exists("connected_server")) {
  try(httpuv::stopServer(connected_server), silent = TRUE)
}
options(
  swc.connected.current_dir = NULL,
  swc.connected.archive_dirs = c(
    "data/diagnostics/daily-explorer-wy2025/preview",
    "data/diagnostics/daily-explorer-wy2026/preview"
  )
)
source("scripts/build-daily-explorer-connected.R")
source("scripts/test-daily-explorer-connected.R")
source("scripts/preview-daily-explorer-connected.R")
```

Wait for the commands to finish, then open <http://127.0.0.1:8805/>. Another
R session's older server must be stopped in that session first. Server revision
`multi-year-v3` prevents silently using the older one-year routing function.
The first two-year build validates both complete archives; unchanged later
builds reuse their verified snapshots and check release seals, file sizes and
timestamps. The separate check script performs full hashes again if requested.

Completed archives take precedence over overlapping dates retained in the
recent cache. A private selection manifest verifies that ownership, while
the current frame retains its original recent context dates for trailing
comparisons. Its source files are unchanged. Cross-year archive context catalogs rebase
neighboring-month metadata to the owning year's mount, allowing WY2025–WY2026
boundary comparisons without loading a full year into the browser. At the
WY2026–current boundary, date navigation works while each source's original
context coverage remains explicit; no absent map is substituted.

Expected local review: two completed years (730 dates), plus actual current
cache dates. The November 25 laptop cache ends October 5, 2026 and retains
five WY2027 dates after completed-year overlaps are removed. This is older
than the VM's operational cache. Review both archive selectors, current return,
September/October boundaries, 7-/30-day views and saved-link reloads. The
connected controller keeps its one-pass restoration, deferred thumbnails and
settled heights; the older standalone archive controller is not used here.

Verification passed November 25: two complete archive years, 730 archive
dates plus five current dates, 25 month routes, approximately 1.54 MB of
navigation/metadata overrides, zero map rebuilds and zero requests. Browser
review confirmed September 30, 2025 shows October 1–3 in its centered view,
Next opens the WY2026 October map, both year selectors work, Current returns
to October 5, 2026, and October 1 current comparisons retain September 28–30
context. Source release seals are unchanged. User visual acceptance is pending.

The sections below retain the earlier single-year pilot's review history.

November 25, 2026. The user accepted WY2025's separate staging archive and
requested a connected local navigation review while the VM's production run
continued. This increment does not access the VM, publish, alter cron, modify
the accepted WY2025 release or rebuild any climate products.

## Review commands

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/build-daily-explorer-connected.R")
source("scripts/test-daily-explorer-connected.R")
source("scripts/preview-daily-explorer-connected.R")
```

Preview: <http://127.0.0.1:8805/>. The build performs full validation of the
existing WY2025 archive; it prints month-level checks and may take several
minutes on the first build. Later builds reuse that full-validation snapshot
when the current-source hashes, archive release digest and all archive file
sizes/timestamps still match, and refresh only the small navigation overrides.
The test script verifies the routing/loading controller, current/UI
checksums, immutable release digest and every archive file's size/mtime against
the fully validated build snapshot. For another full archive hash check:

```r
source("scripts/check-daily-explorer-connected.R")
```

Stop the local server with `httpuv::stopServer(connected_server)` or restart
that R session. The preview uses a read-only local server with mounts for the
existing publication files; it cannot be reviewed by opening index.html
directly or serving only the small preview folder with a generic file server.

## Navigation

- One water-year selector offers the current cached year, any preceding
  September retained in the current cache, and the complete WY2025 archive.
- Month/date controls list actual built dates. Previous/next move by one
  calendar day only. Missing years/dates produce explicit unavailable handling;
  they never jump across a gap to a different date.
- Current conditions defaults to All available dates, retaining the current
  water-year/season browsing behavior. Selecting an individual current month
  scopes that view; archived years always use monthly partitions.
- Current conditions returns to the current cache's latest date. Compatible
  region, variable, display, timeline metric, map view, weather period, report
  timing/window and section-open states carry across switches.
- Saved links retain the selected date/settings. Each month loads only its
  own viewer and the adjacent metadata already supported by the archive.

The default current cache is selected from the normal staged Explorer and
existing local diagnostic viewers, preferring the newest date and then the
most available modules. On this laptop it was the NWS hazards diagnostic
viewer through October 5, 2026. It has reports/hazards but no enabled weather
suite. These are local cache limitations, not a change to production. To
review another already-built current viewer:

```r
options(swc.connected.current_dir = "site/daily-explorer")
source("scripts/build-daily-explorer-connected.R")
source("scripts/preview-daily-explorer-connected.R")
```

If a different R session owns port 8805, stop its old server before previewing
with a different current source. Rebuilding against unchanged source paths
does not need a new map build or transfer.

## Loading behavior

The parent keeps the previous frame height while hiding the old selection
under a loading notice. The new frame applies date/settings before its first
render and becomes ready once the requested date is applied. Optional images
cannot block readiness. Comparison thumbnails load only near the visible
viewport, including when a 30-day view is restored. Height updates settle for 160 milliseconds and
changes smaller than four pixels are ignored. Section-open state is restored,
automatic scroll anchoring is disabled in the changing viewport, and messages
from old frame tokens/foreign origins are ignored. A timeout gives retry and
current-return controls instead of leaving the previous month's map visible.

## Local files and boundaries

Small UI/catalog overrides and a source snapshot are stored under
`data/diagnostics/daily-explorer-connected/`. No PNGs or geometry bundles are
copied there. The server reads them from the existing current viewer and
`data/diagnostics/daily-explorer-wy2025/preview/`. Only manifest-listed archive
assets and selected current publication extensions are served; work caches,
parent paths and writes are rejected. Original source hashes are preserved.

Review current → several archive months → current, October/September edges,
7-/30-day maps, report/hazard windows, saved links, missing dates and narrow
screens. This remains a local UI pilot. A later staging adapter will connect
the standard site entry point and reuse the archive already transferred to
the VM; staging integration and daily retention must pass before production.

Local verification passed: full WY2025 source validation; 16 R adapter/server
checks; routing/controller tests for date gaps, immediate setting changes,
stale-frame rejection and settled heights. Browser review covered current →
winter → monsoon → current; immediate 30-day weather-period carryover; current
full-year/season controls; a September 30/October 1 thumbnail transition;
saved-link reload; and navigation at a 390-pixel viewport without horizontal
overflow. The result uses 365 historic plus 35 locally cached current dates,
with zero downloads/map renders and under 1 MB of new navigation files.

## Restart after the loading correction

Restart the preview server to pick up the revised archive script routes; a
browser refresh alone cannot update an already-running R server:

```r
if (exists("connected_server")) {
  try(httpuv::stopServer(connected_server), silent = TRUE)
}
source("scripts/build-daily-explorer-connected.R")
source("scripts/test-daily-explorer-connected.R")
source("scripts/preview-daily-explorer-connected.R")
```

If another R session owns port 8805, stop the preview in that session first.
Wait for these commands to finish before refreshing the browser. The preview
checks its server revision to avoid silently reusing an older route handler.

The loading correction removes repeated startup renders and the wait for
offscreen lazy images. Timeline rows reserve room for report and hazard
counts, scrollbar space is stable, and height-only messages no longer rewrite
the navigation controls. Browser review confirmed January 31 reloading with
30 days and weather open without requesting its 30 comparison thumbnails at
the top of the page; scrolling into the grid loaded visible rows. The locally
cached current timeline kept identical dimensions across repeated checks.
The accepted archive and current map files remain unchanged.

## January month-cycling correction

The user found an initialization bug with a saved 30-day Map view. The
standalone Explorer's `changeMapView()` intentionally selects the newest
loaded context day when opening that view. A monthly archive also loads
adjacent dates, so January could select February 3 during restoration. The
connected parent interpreted that as another month request, repeating until
September. This behavior was reproduced in the browser November 25.

The connected adapter now changes Map view without changing the selected day,
and applies the requested day after restoring all controls. The parent ignores
different-date messages from a hidden initializing frame; it still accepts
real date/thumbnail changes after the requested page is displayed. Regression
tests execute the real standalone shortcut with the connected adapter at
month/year ends for Single day, 7 days and 30 days, and test stale/default-date
rejection in the parent. This correction touches the local navigation only;
accepted archive maps, source data and production are unchanged.
Browser verification confirmed the original cascade before the correction,
then stable January 31 and January 15 loads with 30 days selected, repeated
7-/30-day switches without changing the date, December-to-January navigation
and a deliberate February 1 thumbnail selection.

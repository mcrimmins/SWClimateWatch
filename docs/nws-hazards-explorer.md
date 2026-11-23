# Local Daily Explorer: reports and NWS hazards

Run from the project root in RStudio:

```r
source("scripts/build-daily-explorer-nws-hazards.R")
source("scripts/test-daily-explorer-nws-hazards.R")
source("scripts/preview-daily-explorer-nws-hazards.R")
```

Review <http://127.0.0.1:8798/>. This writes only under
`data/diagnostics/daily-explorer-nws-hazards/` and the separate source/processed
hazard caches. No staging, publication, site navigation or daily-runner changes
are included. Existing local PRISM maps and report caches are reused. Hazard
requests are bounded to the latest 62 Explorer dates plus one preceding UTC
date; longer histories show explicit unavailable coverage in the hazard row.

## Shared controls and counting

Weather bars retain their existing timeline metric. Two compact rows beneath
each date show storm reports and active NWS hazard events. Both are visible by
default and can be hidden independently. Each row has a label at the left;
legends/counting notes are collapsed by default. Hazard strips show up to three
type colors plus a marker for additional types. Hover or keyboard focus shows
a compact, formatted daily overview. Hazard colors match
the map, stats panel and table, and remain stable across selections.

November 23 hover refinement: native wide text tooltips are replaced by a
viewport-bounded card with one date/region header, the weather value, and separate
report/hazard totals with their three most frequent types. Additional types,
partial coverage and pending refresh are noted compactly. Keyboard focus opens
the same card; Escape, scrolling or leaving the chart dismisses it. One short
selected-day line replaces the duplicated narrative paragraphs beneath the chart.
Detailed type counts remain available in each map's panel and table.


Hazards count once per VTEC event per active day; zone pieces and polygon
updates do not increase the count. Multi-day hazards appear on each active day.
Report counts retain the existing occurrence-based rules. Neither count is a
measure of observed impact severity. Empty and unavailable remain distinct.

Date and region selection are bidirectional between the Explorer and hazard
viewer. The report and hazard timing/window controls are linked. Changing the
main Map view to 7 or 30 days also sets both event windows; Single day resets
them to one day. Event windows can then be adjusted together independently of
the weather image layout. Each timeline cell still represents one reporting day,
using the shared UTC-calendar or precipitation-map timing selection.

Type, level, search and map-extent filters apply to the detailed hazard view;
the timeline always summarizes all hazard types for the selected region and
timing, matching the report-strip convention. Both side-panel and upper All
types controls clear type/level filters without changing shared selections.

## Isolation and geometry loading

November 23 selected-hazard refinement: optional source fields now retain wind
gust tags (mph), hail size tags (inches), tornado/damage tags, hydrologic cause,
severity/record codes, meaningful gauge IDs and true archive emergency flags.
Blank values and placeholders (including severity 0, gauge 00000 and record OO)
are omitted; unknown explicit codes remain labeled. Emergency is an IEM-derived
lifecycle flag, not proof of an emergency during the selected interval. Values
from different matching updates are listed without implying simultaneity.

Selecting a map area scopes details and bulletin candidates to that geometry's
matching segments. Table selection covers the event's matching areas. The primary
button prefers the latest matching non-expiration/non-cancellation bulletin
issued before the selected window ends, falling back to a terminal bulletin
when that is all the archive supplies; if none is available, it opens event history. No separate
bulletin-text downloads are added. Event codes, lifecycle statuses, county/zone
IDs, history and bulletin lists are grouped in collapsed Archive metadata.
Definitions follow [IEM's source schema](https://mesonet.agron.iastate.edu/info/datasets/vtec.html)
and [NWS H-VTEC documentation](https://www.weather.gov/bmx/vtec).

The existing hazard component is embedded in a separate same-origin frame to
prevent its map/styles/control IDs from colliding with the Explorer or LSR map.
The component uses a validated message bridge (origin and source checks) and
loads only when brought into view. Lightweight precomputed timeline summaries
load without fetching hazard geometry. The frame adjusts to its content height,
including the paginated table, rather than adding a second page scrollbar.
Canonical Explorer/report assets are content-versioned in the local output.

The build queries start-time chunks with carry-in snapshots, merges by VTEC
event ID, deduplicates full segments and bundles unique display geometry. The
[standalone pilot's source limitations](nws-hazards-pilot.md) still apply,
including the archive's 30-day carry-in lookback and incomplete message-level
county/zone history. This is retrospective context, not a live warning display.

## Review checks before staging

- Compare precipitation and temperature timeline metrics with both event rows.
- Change date through a weather bar, date buttons, report date and hazard date.
- Change region from either the Explorer or hazard viewer.
- Check 1/7/30-day windows, noon/UTC timing, seasons and water-year changes.
- Verify all-type timeline counts remain independent of detailed type filters.
- Toggle each row and check keyboard focus, row order and narrow-screen scrolling.
- Check hazard selection, colors, reset controls, table and source links.
- Confirm source/rendered publication and daily workflow integration are still
  separate work; these preview scripts never upload.

After local acceptance, use the guarded [VM staging trial](nws-hazards-staging.md).
It builds against the VM's retained dates rather than transferring this preview.

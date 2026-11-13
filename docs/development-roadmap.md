# Development roadmap

Planning review: November 12, 2026. This is the consolidated backlog, not a
commitment to enable every candidate product. No production settings change
when this document is edited.

## Collaboration and scope guardrails

Agreed November 6, 2026: use this document as the shared project roadmap and
the continuing roadmap conversation for new ideas, scoping and prioritization.
Update this roadmap only with decisions explicitly agreed with the user.
Monthly PRISM development is underway in a separate conversation; do not modify
its implementation files as part of roadmap planning.

## Operational baseline

The user confirmed the November 4 morning production run published release
`e4ec458d049417e567ba182eb824d4070b8d4e0e`. Production runs daily on the AWS VM;
the laptop remains the development environment, with a separate VM staging
checkout and S3 prefix for testing releases.

Live features include:

- Configurable Home dashboard with map-matched regional summaries, linked
  condition cards, and a current three-month RONI card with separate CPC status.
- Daily Explorer precipitation/temperature maps, synchronized date/timeline/
  single-day/7-/30-day views, weather grids, and archived forecast-discussion
  links with an embedded reader.
- Daily CORe 500-mb heights, 250-mb jet/flow, and PWAT/sea-level-pressure/
  terrain-screened 850-mb-flow maps. Bounded same-source recovery addresses
  selected broken pressure indexes; coverage and withheld overlays are audited.
- Trailing 7-/30-day versions of all three weather maps, integrated into the
  daily workflow and confirmed in production November 12. Missing CORe dates
  and affected means are automatically retried with persistent bounded queues.
- Station Conditions for 62 records (51 mapped), with linked daily charts,
  temperature normals and daily records, selected-period CSV downloads,
  period extremes/historical standing and freeze nights. Water-year,
  cool-season and monsoon precipitation comparisons include historical bounds,
  year selection and closest progression. Monthly climatology offers 1991-2020
  and full available record distributions with linked tables and coverage.
- Current Snow observed SWE, absolute departure, supported percent of median,
  and exact seven-day net change. Historic peak SWE and snow-covered-day maps
  are published; seasonal snow anomaly companions remain local pilots.
- Home Maps/Synopsis tabs and the standalone template synopsis, including
  seasonal snow storage/change highlights, dated supporting evidence for every
  quantitative selected bullet, and matching maps for selected seven-day
  temperature departures. AI synthesis remains deferred.
- PRISM attempts yesterday's complete maximum/minimum/precipitation set and
  falls back when it cannot validate the complete set.

The November 3 staging update took 55m 10s with changed inputs and catch-up
work. It validated 51/51 current and 352/352 historic maps. Weather had 61/63
Explorer dates and 28/30 recent dates, with two pending dates despite the latest
map reaching November 2; inspect those date-specific gaps rather than assuming
the archive is complete. These are staging measurements, not timings for the
November 4 production run. Record the production cumulative/cache timing when
available. Production changes still require local checks, a committed release,
VM staging review and explicit promotion.

### November 8 release review

The user confirmed successful production publication of monthly integration
release `e78825a46737b7adff7f999032f3ffa9fcc2834c` in the project conversation
**Design PRISM RCC-ACIS downloads**. This release includes the earlier Analytics,
station annual precipitation bars and deterministic template synopsis commits.
The previous production-promotion wait is closed; GA4 Realtime collection still
needs separate confirmation. Regional snow narrative was still a follow-up at
that review; its production completion is recorded below. AI remains deferred.

The reported production run finished successfully in **12m 50s** (runner elapsed
771 seconds). It validated **51/51 current and 352/352 historic maps**, updated
62 station records (51 mapped), and reused all 68 Daily Explorer dates/476 maps.
Weather reached November 7 with **30/30 recent and 68/68 Explorer dates**, zero
pending dates and no withheld/unknown wind overlays. This resolves the previously
reported weather coverage gaps at this snapshot; continue monitoring freshness.

**Monthly Climate is live through October 2026:** temperature rankings,
precipitation rankings and SPI at 1-/3-/6-/12-month durations. The completed cycle
made zero new requests and took about one second in the production daily run.
`SWC_MONTHLY_MAPS=true` enables updates within the existing daily cron, with
days 1–5 availability/revision checks, no further requests after cycle success,
retained verified maps on failure and overdue warnings/manual catch-up after
the window. No second cron is needed. The next automatic cycle targets November
2026 during December 1–5. External Drought and Grazing hotlink exports and link
replacement are not confirmed complete by this production report.

**Navigation/About/SPI-footer patch: now live.** The subsequent production
promotion includes the earlier `7fbd6e4` navigation/grouping, Home cleanup,
About-page/SPI-method documentation and SPI-footer changes. The user confirmed
that the resulting production site looks good on November 9. The original
local SPI display refresh rebuilt four maps, reused eight ranking maps and all
four fits, and made zero source requests. See the
[patch release guide](spi-footer-about-release.md).

### November 9 production synopsis follow-up — complete

The user confirmed successful production publication and review after staging.
This closes the regional snow narrative and supporting-link work:

- Seasonal snow storage and exact seven-day net SWE-change highlights use
  explicit AZ/NM area, reference, coverage and recency guards.
- Every selected quantitative bullet has a dated supporting page; a selected
  seven-day temperature claim has its own matching departure map.
- Seasonal selection, a maximum of three bullets per section, source-specific
  dates, unsupported-claim withholding and success-only comparison snapshots
  remain in place. Fictional cases and review candidates remain unpublished.
- The site-only publisher now reconciles Monthly Climate from verified local
  cached releases before rendering, repairing page/asset mismatches after
  checkout. An already matching release uses the fast checksum-only path.

Local tests and all 31 fictional seasonal review cases passed. A local cached
two-pass staging check passed in 17.03 and 9.52 seconds, with identical supporting
outputs and snow-cache reuse. These are laptop smoke-test timings, not a new
production-run benchmark. The exact final VM commit hash and production elapsed
time were not supplied with this confirmation; do not infer them from local HEAD.
No downloads or AI calls were added for the synopsis increment. Continue routine
monitoring of source freshness, reference support, storage and daily timing.

See [implemented synopsis scope](conditions-synopsis-scope.md#november-9-production-increment-linked-evidence-and-snow-context).

### November 10 stable map links — production promotion confirmed

The user expanded stable image URLs from the two Drought and Grazing products
to **all published map images** for reuse by other projects. The user confirmed
production promotion November 10. The release adds predictable `maps/latest/` endpoints for rolling products and a searchable
HTML/CSV/JSON catalog covering both rolling and dated maps. Current PRISM, snow,
all twelve monthly products, daily PRISM maps, CORe maps, historic-season maps
and selected weekly-temperature support maps are included. Original URLs remain
available. Missing/disabled latest products use notice images; integrity checks
run after normal publication validation and optional weather quarantine. Aliases
reuse existing PNGs, with short requested caching and no new source downloads.
Local tests and staging review passed. The supplied staging HTTP check confirmed
200, image/png and the requested public,max-age=300,must-revalidate response.
Production promotion is user-confirmed; no production header output or full-run
timing was supplied. External dashboard embedding and an Arizona-only export
are not confirmed complete and remain separate follow-ups. See
[stable map link contract and review steps](map-hotlinks.md).

### November 12 station enhancements - production confirmed

The user confirmed that the promoted production Station Conditions page looks
good after staging review. This closes the station enhancement release:

- Linked daily precipitation/temperature dates, compact normal/record tables,
  visible new/tied record indicators and selected-period daily CSV exports.
- Period extremes and historical standing grouped directly below the daily
  charts. One collapsed seasonal comparison group opens both precipitation
  plots; its explanatory note remains separately collapsed inside.
- Monthly climatology in its own collapsed section, defaulting to 1991-2020,
  with a full available cached-record alternative and calendar/water-year order.
- Precipitation medians/IQR boxes and actual min-max whiskers; temperature mean
  high/low lines with IQR and min-max envelopes. Linked month tables include
  summary statistics, tied extreme years, sample counts and eligible spans.
- Cached reference preparation is integrated into the standard daily station
  build. Finished-month, coverage, snapshot/date and publication-asset guards
  remain in place; browser selection/export makes no source requests.

Production completion is user-confirmed November 12. The final release hash,
publication elapsed time and subsequent automatic-run cache statistics were not
supplied with this confirmation; do not infer them from laptop HEAD. Check the
next scheduled run for publication success, cache reuse and timing. Further
station climatology/heat extensions remain separate backlog items below.

## Priority order and working sequence

This is the proposed working order, with one feature increment active at a time.
It preserves all backlog items below; priority is not a commitment to deliver
every candidate. A deadline for the external monthly-map deliverable would move
that work ahead of discretionary features.

| Priority | Work | Next bounded step and completion evidence |
| --- | --- | --- |
| P0 — ongoing operations | Monitor the confirmed production release | Weather means and automatic retries join the station enhancements/monthly climatology confirmed live November 12. Check the next scheduled run's timing, cache reuse, retry-queue changes and source freshness. GA4 Realtime collection still needs confirmation. |
| Complete — monitor | Template conditions synopsis | Seasonal snow narrative, dated supporting evidence and matching weekly-temperature maps are confirmed live November 9. Retain seasonal tests, reference/coverage guards and successful-publication comparisons. AI and the daily AI page remain deferred. See [scope](conditions-synopsis-scope.md). |
| Complete — monitor | Stable URLs for all published map images | User confirmed production promotion November 10. Predictable latest endpoints, dated links, searchable HTML/CSV/JSON catalog and publication integrity checks are live. External project embedding and any Arizona-only export remain separate follow-ups. See [contract](map-hotlinks.md). |
| Complete — monitor | Station seasonal precipitation histories | Water-year, cool-season and monsoon comparisons are confirmed live. Retain completeness guards, matching-date comparisons and the hatched incomplete current-season bar. Regional historical maps remain separate. |
| Complete — monitor | Recent-period weather means and automatic retries | User confirmed production November 12: 7-/30-day 500-mb heights, 250-mb jet/flow and PWAT overlays; daily integration, cached reuse, revision invalidation, persistent CORe/mean retries and reporting. Weather anomaly baselines remain separate. |
| P1 — recommended next increment | Historic seasonal snow anomalies | Review the existing WY2005/2018/2024 pilot, validate peak-SWE departure/percent-of-median references and support guards, then prepare a small historic-page staging release. Reuse completed seasonal grids; no new daily downloads. |
| Complete — monitor | Station daily-chart normals, records and interactions | Daily normals/records were confirmed live November 10. Linked chart dates, selected-period CSV exports and the seasonal disclosure/layout refinements are also confirmed in production November 12. Retain coverage and source-record safeguards. |
| Complete — monitor | Monthly station climatology | Confirmed production November 12: 1991-2020/full-record selection, monthly distributions/extreme years, linked tables, coverage and calendar/water-year ordering. Daily annual-cycle climatology views remain optional future extensions. |
| After existing commitments — 3 | Climate of the region page | Start with 1991–2020 annual and seasonal precipitation normals and temperature averages when the required PRISM inputs are available. Historical extremes follow separately. |
| Deferred until spring 2027 | Station heat metrics | Scope station-appropriate temperature thresholds, counts and departures; reuse existing hot-day/warm-night screening. No implementation before spring 2027. |
| Alongside increments | Operational maintenance | Track freshness and source revisions, station audit age, raster warnings and measured cache/runtime behavior. Address specific failures promptly; schedule broader profiling as its own bounded task. |
| Later — scope before building | New sources and statistical extensions | Local storm reports/hazard polygons, gauge conditions, historical odds, completed-year Explorer/historic-season integration, custom station dates, ENSO composites and further SPI products. Each needs its own source/method/performance assessment. |
| Later — feasibility exploration | Interactive raster map page | Explore selectable existing raster products over a basemap, adjustable transparency, zoom/pan and pixel-value queries. Benchmark a small static-site pilot before selecting delivery methods or scheduling implementation. See [scope](#new-exploration-interactive-raster-map-page). Existing commitments and agreed climatology order remain unchanged. |
| Later — polish | Consistency and optional interactions | Shared city-label styling, historic RONI labels at the next archive refresh, custom Analytics events and remaining documentation reconciliation. |

November 12 recommended working sequence: station enhancements, monthly
climatology, daily weather means and automatic retries are confirmed live.
Monitor the next scheduled run, then return to historic seasonal snow anomaly
companions as the next bounded feature increment. First review the existing
three-year pilot and its references/masks before expanding historical pages.
The regional climatology page follows the agreed climatology sequence; the
interactive raster pilot remains a separate later increment. Heat metrics stay
deferred until spring 2027. External dashboard links/Arizona-only exports, GA4
Realtime and the first automatic December monthly cycle remain follow-ups.

### Daily weather means and automatic retries - production confirmed

The user confirmed the production release on November 12, 2026, after local
review, VM staging tests and promotion. **Feature delivery is complete.**
The production commit hash and new VM timing/coverage logs were not supplied
with this confirmation; do not infer them from laptop HEAD or pilot timings.

The live Daily Explorer includes daily, trailing 7-day and trailing 30-day
weather maps for:

- 500-mb heights with consistent colors and 6-dam contours.
- 250-mb jet/flow, averaging wind components before calculating speed and
  streamlines; this is not mean scalar speed or an extreme-wind product.
- PWAT with mean sea-level-pressure contours, terrain-screened 850-mb flow
  and H/L labels calculated from the selected period's mean pressure field.
  These are not tracked storms, surface winds, precipitation totals or IVT.

Periods use complete UTC days and all eight three-hour samples per day, native
Gaussian coordinates and shared map scales. No partial means, missing-day
filling or date substitution. Wind arrows require above-ground support at
every sample in the period. Anomaly maps/baselines remain separate future work.

Weather period controls averaging; Map view controls the grid of individual
days. Shared date controls, timeline, season/year changes and weather tabs
remain synchronized. Clicking a daily weather tile selects Daily. Missing
means offer Show daily map only when that exact daily map exists.

The existing daily VM runner updates daily CORe first, then builds/reuses
means from cached numeric fields. Source/output hashes invalidate affected
windows when inputs change. The default cap is three new/revised endpoints
per run, with checkpointed backlogs; there is no recurring historical download
for the means calculation. Runtime/count summaries appear in console and ntfy.
Mean failures disable only the means selector, preserving daily weather and
core publication. Staged/rendered manifest and PNG integrity are validated.

Automatic retry coverage is also complete:

- Missing/failed CORe dates persist in archive state and a visible retry queue.
  Least-recent attempts receive slots alongside the newest date; older gaps
  cannot be continually displaced by new failures.
- Failed dates refresh upstream indexes and selected fields, including after
  upgrade from an older archive state, rather than reuse a cached failure.
- Missing required mean inputs queue daily-date repairs even when daily PNGs
  already exist. Means retry after those input repairs.
- Deferred/unavailable mean endpoints stay queued beyond the recent 30-endpoint
  selection while retained in the Explorer. Completed repairs clear queues;
  build/request limits and complete-window safeguards remain in force.

Operational records:

- `data/processed/weather-circulation/{last-batch,retry-queue}.csv`
- `data/processed/weather-period-means/{workflow-status,last-batch,needed-dates,retry-endpoints}.csv`
- [Weather workflow, staging and promotion runbook](weather-period-means-staging.md)
- [Publishing configuration and retry behavior](publishing.md)

Tests cover missing-date recovery on subsequent runs, refreshing failed source
indexes, rebuilding both means after input recovery, retry fairness, aging
endpoints, revisions, cache reuse, selector combinations and publication
integrity. **Ongoing monitoring:** record the next scheduled run's timing,
cache reuse and queue changes; distinguish upstream delay from software errors.
Successful publication does not imply every source date is available.

Local prototypes remain reproducible with the seven-day, period-means and
combined Explorer preview scripts. Their default example ends October 5,
2026; these preview dates are not the production freshness date. The initial
nine-map period suite transferred 9,352,933 bytes for 99 missing selected
fields and took 55.71 seconds including acquisition; unchanged reuse took
2.16 seconds. These are laptop measurements, not production performance.

## Agreed additions and enhancements

**Historic ENSO labels at next archive refresh (October 28 request):** apply the
home card's neutral/weak/moderate/strong/very-strong RONI magnitude bands to each
historic page's documented DJF value, preserving its period, source version and
snapshot provenance. Use index-range wording rather than declaring an episode
from one value. Any historical official-status statement must use a source
applicable to that season; never copy today's CPC advisory onto historic years.
The current home card now separates latest three-month RONI magnitude from the
dated CPC operational status. Historic pages have not been regenerated for this
labeling change; include source checks, label tests and rendered review when
those pages are next refreshed.

| Workstream | Next bounded step | Relative effort |
| --- | --- | --- |
| Conditions synopsis / daily text summary (requested November 4, 2026) | Confirmed live November 9, including seasonal snow highlights and dated evidence links for quantitative selected bullets. Matching seven-day temperature maps and resource-integrity checks are included. Retain routine seasonal/source monitoring; AI remains deferred. See [implemented scope](conditions-synopsis-scope.md). | Complete; monitor |
| Recent-period weather means and anomalies (requested November 2, 2026) | 7-/30-day circulation/moisture means, daily updates and automatic retries are confirmed live November 12. Monitor runtime, revisions and source gaps. Calendar-matched anomaly baselines remain a separate feasibility/methods task. | Means/retries complete; anomalies deferred |
| Station water-year precipitation curves (requested November 1, 2026) | Live November 4 for 62 records: current cumulative precipitation, historical-year selection, WY1991-2020 mean and middle-50% band, record bounds, closest progression and interactive inspection. Historical/reference caches support daily builds. Review production cache timing; optional background curves remain deferred. | Live; monitor |
| Historical seasonal and water-year time series (requested November 1, 2026) | Water-year, cool-season and monsoon station histories are confirmed live. Completed-year totals and a supported normal line reuse the cumulative-history catalog; the hatched current season-to-date bar is excluded from full-year comparisons. Regional summaries remain separate. | Station histories complete; monitor |
| Historical odds of reaching precipitation thresholds (requested November 1, 2026) | Pilot CW3E-style climatological probabilities of reaching fractions of full water-year normal given precipitation already observed. Validate Southwest seasonality, historical samples and uncertainty; benchmark cached historical remainder distributions before selecting monthly or daily updates and maps. | Moderate-large; methods validation first |
| Google Analytics (requested November 1, 2026) | Tag G-XS7RFBPW01 is included in the confirmed production release, gated to the production hostname/path and top-level views. Local/staging exclusions and embedded deduplication tested; GA4 Realtime collection still needs confirmation. See site-analytics.md. Custom interaction events remain deferred. | Collection verification pending |
| Historical snow anomaly companions | Validate seasonal peak-SWE departure and percent-of-median pilots, then stage all eligible WY2005-WY2025 years. Retain coverage and support guards and existing archive cautions. | Moderate |
| Raster plotting warnings | Locate affected builders and correct the rendering geometry without altering climate statistics. Compare before/after maps. | Small-moderate |
| Daily-update speed | Profile several consecutive new-date runs, cache-hit/miss behavior, costly PRISM reference work, and station processing. Benchmark before removing products or changing cadence. | Moderate |
| SNODAS source revisions | Define a bounded recheck policy for already processed archives, provenance changes, and affected reference/map invalidation. | Moderate |
| Completed-year Daily Explorer | Decide what remains public at water-year rollover, then test dated manifests, navigation, retention, storage and rebuild costs before historical backfill. | Moderate-large |
| Station metadata and additional extremes | Scope station/component history and historical extremes comparisons. Calendar-date plot records and the station climatology section are now bounded increments in the [November 6 scope](#station-and-regional-climatology-agreed-november-6-2026); heat metrics are deferred until spring 2027. Any additional formal indices need explicit periods, thresholds, completeness, ties and baseline definitions. | Variable |
| Station custom date periods | Assess a start/end-date selector alongside presets, initially bounded to the recent daily data already published. Separate basic summaries from historical comparisons; benchmark map/table recalculation, lazy loading, payload size and browser responsiveness before implementation. | Moderate; full historical comparisons substantially larger |
| Interactive raster map page (requested November 8, 2026) | Explore existing numerical map rasters on a basemap with product selection, opacity control, zoom/pan and pixel queries. Reuse current caches, map definitions and static publishing; measure payload, interaction speed and build/storage costs before committing to implementation. See [scope](#new-exploration-interactive-raster-map-page). | Feasibility first; effort depends on raster delivery |
| Shared city-label styling | Consider the smaller Daily Explorer labels for other maps; review representative precipitation, temperature and snow backgrounds before a site-wide rebuild. | Small-moderate |
| Station audit maintenance | Establish a repeatable full-record audit refresh cadence, visible audit age and automatic cautions; avoid a manual station-by-station approval requirement. | Moderate |
| Product freshness visibility | Weather activation/coverage audit is live. November 8 production reports 30/30 recent and 68/68 Explorer dates with no pending dates or withheld/unknown wind overlays, closing the earlier coverage-gap follow-up at this snapshot. Monitor recurrence; extend source-specific freshness reporting to PRISM, snow and stations later. | Small-moderate |
| Internal documentation reconciliation | Replace obsolete manual/unpublished/two-snow-map descriptions or clearly mark them as historical pilot instructions. Preserve useful reproducibility details. | Small |
| ENSO/RONI composites and analogs | Define season, variable, reference and sample membership before implementing configurable comparisons. | Large |
| Validated SPI module | Separately validate fitting, zero precipitation, reference period and SPI-1/3/6/12 behavior; do not substitute raw standardized precipitation anomalies. | Large |
| Daily weather and circulation diagnostics | Daily and 7-/30-day three-map CORe integration, retained backfill, automatic gap/mean retries and publication checks are live. Monitor source availability, queues and cache/runtime behavior. Anomaly baselines/additional fields remain separate; IVT remains deferred. | Live; monitor |
| Archived forecast discussions in Daily Explorer | Date-bound AFD/WPC links and the fixed-size embedded reader are live and user-tested. Metadata indexing and optional SPC/report sources remain future work. | Indexing effort pending |
| Long-term monthly PRISM maps | Monthly Climate rankings and SPI plus automatic revision-aware updates are live. January 1895–October 2026 inputs are verified. External hotlink exports remain to close; the requested monthly-based Historic Years rebuild and regional climate normals page remain separate future work. | Core release live; extensions scoped separately |
| Local storm reports and watch/warning polygons | Scope archived reports and NWS hazard polygons alongside Daily Explorer and/or seasonal summaries, including event-time matching, deduplication, data availability and efficient caching. | Longer-term; scope first |
| Historic-season station and Daily Explorer content | Decide which station summaries, extreme-event views and daily-map navigation belong in historic seasons; define retention, completeness and storage limits. | Longer-term; scope first |
| Hydrological observations and gauge-condition maps | Assess gauge data access, station coverage and useful streamflow/stage condition metrics, with historical context and bounded update costs. | Longer-term; scope first |
| Hydroclimate home dashboard | Dashboard layout, map-matched summaries, linked condition cards and RONI/CPC context are live. Separately scope regional cumulative precipitation versus normal with cached calculations and a runtime benchmark. | Live layout; regional evolution chart moderate |

## New exploration: interactive raster map page

Requested November 8, 2026: explore a dedicated interactive map page where users
select existing map-data rasters, display them semi-transparently over a basemap,
zoom/pan and query pixel values. It must be fast and efficient within the current
project framework and complement Current Maps, Daily Explorer, Monthly Climate
and Station Conditions. Record this as feasibility work; preserve existing
commitments, the agreed climatology sequence and the spring 2027 heat deferral.
No implementation or production dependency is enabled by this entry.

### User experience and data meaning

Scope an initial single active raster with product/available-period selection,
opacity control, a matching legend, reset-to-region control and click/tap value
readout. Retain selected map extent when changing compatible layers. Show units,
data-through date, exact period, source, reference period and native resolution;
link to the corresponding existing product/methods page. Keep static maps for
quick comparisons and sharing, Daily Explorer for time-based browsing and
Station Conditions for observations at stations. Additional simultaneous layers,
animation, arbitrary calculations and full historical browsing need separate
scope after the basic interaction is proven.

Inventory retained numerical rasters for existing products first: published
plot PNGs alone cannot supply exact climate values. Query the source-grid cell,
not a color or a smoothed display value. Preserve missing/withheld-data masks,
supported precision and percentile/rank/SPI distinctions. Show categorical
labels separately from numerical values; zooming must not imply finer source
resolution. Validate map alignment/reprojection and queries at known cells,
grid edges and missing-data boundaries.

### Framework fit and performance assessment

Prefer a static Quarto/JavaScript page and the existing S3 publication workflow,
reusing the station map's Leaflet experience where suitable. Compare compact
regional raster delivery with transparent georeferenced display assets plus
numeric query data; assess tiled/overview GeoTIFF delivery only if measurements
justify it. A plotted PNG with axes/legend is not a georeferenced overlay.
Verify actual hosting support for range requests, cross-origin access and
browser caching where required. Select a production-appropriate basemap with
attribution and documented usage terms; retain clear behavior if it is unavailable.
Do not introduce a live R/Shiny service or browser-triggered climate downloads
as the default approach.

Lazy-load only the selected product/period, bound browser memory/cache growth
and reuse unchanged versioned assets. Rebuild only affected derivatives from
existing validated caches; do not duplicate source acquisition or publish the
entire history for one view. Measure cold/cached first display, layer switching,
pixel-query latency, pan/zoom responsiveness, transferred bytes, browser memory,
published storage and incremental build/upload time on desktop and mobile-class
devices. Use the agreed initial products and acceptance targets below; compare
queries against their numerical sources, then review the local pilot and cost
report before choosing architecture or expanding scope.
Monthly PRISM implementation files remain outside this roadmap task.

### Initial pilot scope and acceptance targets: agreed November 8, 2026

Use existing saved numerical rasters from the completed October 2026 release,
with one active layer at a time and the map position retained on layer changes.
Reuse cached products without new climate calculations or source downloads.

| Pilot product | Purpose | Pixel readout |
| --- | --- | --- |
| October 2026 precipitation total | Intuitive amounts, dry cells and spatial rainfall variation | Total inches; matching percentile if included |
| 12-month temperature ranking ending October 2026 | Ranked colors and distinct record categories | Mean temperature, percentile, rank and comparison-year count |
| SPI-12 ending October 2026 | Continuous negative/positive index values and withheld cells | SPI value, exact period and unavailable-data explanation |

These are acceptance targets to measure, not achieved performance results.

| Measure | Initial pilot target |
| --- | --- |
| First usable map, including first queryable layer | At most 3 seconds on desktop; 5 seconds on mobile |
| Switch to an uncached layer | At most 2 seconds |
| Switch back to a cached layer | At most 300 milliseconds |
| Click/tap value readout after the layer loads | At most 100 milliseconds |
| Opacity adjustment | Visible feedback within 100 milliseconds |
| Pan/zoom | Aim for 60 frames/second; sustain at least 30 on the mobile test device |
| Initial transfer, excluding basemap tiles | At most 2 MiB for the page, libraries and first layer |
| Additional product transfer | At most 1 MiB per selected product, including query fields |
| Added browser memory | At most 100 MiB, with no continuing growth after repeated switches |
| Unchanged publication run | Zero raster rebuilds/uploads; manifest checks at most 5 seconds |
| Changed three-layer release | Added preparation at most 30 seconds; published pilot assets at most 10 MiB |

Test on the laptop and a representative phone with empty and warm caches.
Include a reproducible simulated mobile connection of 10 Mbps and 100 ms
latency; record basemap traffic separately. Report slower results as well as
averages and distinguish map readiness from completion of background loading.

Correctness is a separate pass/fail requirement: sampled query values must
match saved source cells within stored precision, missing/withheld cells must
remain missing, record display codes must never be presented as percentiles,
and zooming must preserve alignment without implying finer source resolution.
The framework-fit decision requires the agreed performance and correctness
targets using the existing static website/publication workflow, browser-side
queries and no new live service. Test compact raster delivery first; introduce
tiles only if measurements justify the added work.

Snow SWE is a possible subsequent stress test for a different grid,
higher-resolution delivery and snow-specific masks, after the initial pilot
passes; it is outside this three-product increment. Existing implementation
priorities, the agreed climatology order and the spring 2027 heat deferral
remain unchanged. This entry authorizes the pilot scope for future work, not
implementation or production integration in this roadmap task.

## Station and regional climatology: agreed November 6, 2026

Keep existing release/synopsis commitments and all four P2 projects ahead of
these additions, including Monthly PRISM, station seasonal precipitation
histories, recent-period weather means and historic seasonal snow anomalies.
Implement the additions in the order below, with heat metrics deferred until
spring 2027. This expands existing station-extremes, historical-time-series and
long-term PRISM ideas; it does not authorize changes to Monthly PRISM
implementation files in this roadmap conversation.

### 1. Station daily-chart normals and records

Confirmed live November 10, 2026, commit `9db345c182d98fa7fb30a962c6bbe85fb62253dc`.
Temperature charts show smoothed project-calculated 1991–2020 normals and earlier
calendar-date records, filled new/tied markers and daily comparison tables.
Precipitation shows observed/earlier-record tables and colored/striped record bars.
Historical standing is grouped with period extremes. Production publication passed
54 current and 352 historical maps.

Confirmed production November 12: one collapsed seasonal comparison
group opens both plots, with the methods note separately collapsed inside. Daily
precipitation and temperature selections are linked, including day buttons and
keyboard controls. A selected-station/period CSV includes observations, quality
labels, normals and earlier-record references from already loaded data. No new
source requests or scheduled calculation step is added by these interactions.

Implemented design: daily temperature charts include normal high/low lines,
earlier eligible calendar-date record values and new/tied markers, with compact
hover/readout details. Daily precipitation uses an earlier-record table and
colored/striped record bars; a background record curve was not added. The period
extremes remain distinct from calendar-date records. Normals are project-
calculated from 1991-2020; record references use eligible earlier station years,
with documented coverage, ties, leap-day and missing/flagged-value rules.
Accumulated precipitation reports are ineligible as individual daily records.
Fixed stations and ThreadEx histories keep their identities. The completed
monthly climatology section shares the cached-observation screening principles.

### 2. Monthly station climatology - complete; extensions remain scoped

Confirmed live November 12 after local and VM staging review. The collapsed
"Typical climate at this station" section supports 1991-2020 (default) and full
available cached station/ThreadEx history, with Jan-Dec / Oct-Sep ordering.
Precipitation requires complete calendar months; paired temperature months
require at least 95% valid days and no gap over two days. At least 20 eligible
years are required independently per month/variable. Actual leap-day reports
enter February; unfinished months and observations after the snapshot are
excluded. Unsupported results remain unavailable, and zero remains zero.

Precipitation uses a median mark, 25th-75th percentile box and actual min-max
whiskers, without a 1.5-IQR outlier rule. Temperature uses mean high/low lines,
IQR bands and lighter min-max envelopes for monthly means. Short hover labels
and linked month tables show values, extreme years, counts and eligible spans.
Selection persists when changing reference period or month ordering. These are
project-calculated references, not official NOAA normals. Temperature endpoints
describe monthly means; extrema always belong to the selected reference period.

Both periods are precomputed and cached at
`data/processed/acis-stations/monthly-climatology/`. Historical revisions or a
new completed month invalidate affected inputs; incomplete-current-month appends
do not. Standard station builds prepare these references automatically, with
no additional source requests. Publication checks require both datasets,
matching station/snapshot information, coverage, ordered ranges and linked
assets. No separate cron entry is needed. Monitor the next daily run for reuse.

Local refresh: `scripts/build-station-climatology-integration.R`; standard
preview: `scripts/serve-station-conditions-review.R`. The isolated pilot remains
available through `scripts/build-station-monthly-climatology-preview.R` and
`scripts/serve-station-monthly-climatology-preview.R`.

Remaining optional station-climatology extensions: full annual-cycle daily
normal high/low/mean curves, daily precipitation averages/record views, wet-day
frequency, typical wet-day amount, freeze frequency and first/last-freeze
distributions. These are distinct from the completed monthly section; scope
methods, coverage and cost before building. Growing-degree days need a defined
audience/method. Heat counts remain deferred until spring 2027.

### 3. Climate of the region page

Create a regional climate-context page, beginning with 1991–2020 precipitation
totals and temperature averages for annual and JFM/AMJ/JAS/OND seasonal maps,
with short explanations of elevation and seasonal contrasts. Reuse suitable
PRISM normals/monthly inputs when available from the separate workstream.
Cool-season and monsoon summaries are later options to coordinate with station
seasonal histories.

Avoid duplicating annual precipitation-normal maps solely to switch calendar-
year/water-year labels: both complete cycles contain the same twelve monthly
normals. Water-year ordering remains useful for accumulation curves and
individual-year histories. Historical wettest/driest years and warmest/coldest
seasons are separate follow-ups with explicit comparison periods. Monthly
PRISM high/low temperatures are averages of daily highs/lows; they cannot
establish daily temperature or rainfall records.

### Deferred until spring 2027: station heat metrics

Revisit spring/summer station counts above thresholds such as 100°F and 110°F,
with station-appropriate choices and explicit greater-than versus at-or-above
definitions. Calculate departures from matching season-to-date counts in
1991–2020 with completeness guards. Complement the existing percentile-based
hot-day/warm-night indicators and reuse their screening where appropriate.
This is a deferred planning item, not an active implementation commitment.

## New exploration: Google Analytics

Requested November 1; tag `G-XS7RFBPW01` passed staging November 4, 2026
and is included in the confirmed November 8 production release. Collection
still awaits verification in GA4 Realtime. See
[Analytics setup and validation](site-analytics.md). Add Google Analytics
to understand which SW Climate Watch pages and tools are useful to visitors.
Start with page views and referral sources; separately choose a small set of
interaction events such as Explorer date/variable selection, station selection
and full-resolution map downloads. Confirm the property owner and measurement
ID, applicable University privacy/consent requirements, and treatment of local
previews, staging and developer traffic before implementation. Avoid sending
personal information in event parameters. Test collection and duplicate-event
handling before production activation, and preserve site responsiveness without
adding climate-data downloads or recurring R processing.

## New exploration: daily weather and circulation

See [daily weather and circulation scope](weather-circulation-scope.md).
**Status November 4, 2026:** the original two-map feasibility pilot has advanced
to the three-map production integration described above. See the scope and
[daily workflow](weather-circulation-daily-workflow.md) for measured costs,
source recovery, retained backfill and the opt-in release procedure.
Requested uses include precipitation occurrence/patterns/extremes, temperature
patterns/extremes, wind events, at least a 500-mb map, subtropical jet extension
and summer monsoon-high position. Reuse the existing precipitation/temperature
products instead of creating another competing observation stream by default.

Winter/summer and recent-date pilots have been reviewed, and CORe is the selected
source for the production daily weather maps. ERA5 remains a potential comparison
or historical-analysis source. IVT was deferred because of its daily overhead.
Weather climatology/anomalies and completed-year Explorer navigation remain
separate projects; this document does not enable production configuration.

### Recent-period mean weather and circulation maps

Requested November 2, 2026; **absolute 7-/30-day means and automatic retries are
complete and confirmed in production November 12**. Daily Explorer's Weather
period selector covers 500-mb heights, 250-mb vector-mean jet/flow and PWAT with
sea-level-pressure/terrain-screened 850-mb-flow overlays. Exact UTC averaging
dates, complete samples, native grids and clear separation from the daily
thumbnail grid are implemented. Means use cached numerical fields, not PNGs.
Pressure centers are calculated from the period mean rather than copied from
daily maps. See the production completion section above for retry behavior.

The remaining work in this entry is **anomaly-baseline feasibility**, not more
absolute-mean integration. It remains separate from current operations and is
not the next feature increment ahead of the existing snow commitment.

Anomalies need a separate, documented reference: assess the available CORe
record, a fixed climatological period, calendar matching/smoothing, leap days,
grid consistency and equal-length historical windows. Start by considering
500-mb height and PWAT departures; assess whether raw or standardized departures
are useful for each variable, with adequate sample support. Absolute heights
are not anomalies, and mean wind-speed anomalies differ from vector anomalies.
Keep ENSO/teleconnection interpretation descriptive unless separately validated.

If this deferred anomaly work is selected, start with baseline feasibility,
then a small winter/monsoon anomaly pilot. Benchmark one-time historical
downloads, reference storage and daily rendering/invalidation costs. Cache
reference products; do not add recurring historical baseline downloads to the
production job. Continue routine seasonal review of the live mean maps.
No new maps or daily processing are enabled by this entry.

## New exploration: archived forecast discussions

See [discussion archive scope](forecast-discussion-scope.md) for feasibility,
source links and separate scoping/implementation checklists. This future item
can proceed independently of circulation-map downloads. The original links-only
panel has been extended with the reviewed embedded reader. It uses explicit UTC issuance-day searches
with clear forecast-versus-observation labeling. Exact-issuance metadata and
optional SPC/report products remain separate follow-ups.

## New exploration: Station Conditions custom date periods

Requested October 25, 2026; scoping only, not active implementation. See
[station period-selector scope](station-explorer-prototype.md#future-scope-custom-date-periods).
A bounded recent-date selector is feasible in principle without new climate
downloads, but arbitrary-period ranks/anomalies are not available from the
currently published preset results. Preserve the fast default preset view;
do not publish full station histories or precompute every possible date range.

## Longer-term scope additions: October 27, 2026

These entries began as future scoping. Monthly PRISM has since advanced to
production as recorded below; other extensions remain subject to their own
scope and review. Estimate source access, runtime, local/public storage and
browser costs before selecting another pilot.

### Monthly PRISM: long-term climate record

**Current status, November 8:** Monthly Climate and the revision-aware daily-runner
integration are confirmed live through October 2026. The latest navigation/About/
SPI-footer patch passed staging review; production completion is unconfirmed.
See the [current release review](#november-8-release-review) for production timing,
coverage, scheduling and remaining external-deliverable work. The dated pilot
and staging notes below preserve development history; their earlier “not enabled”
and “next integration” statements are superseded by this status.

November 6: the [monthly access/cache pilot](prism-monthly.md) is implemented
locally. The user has now verified all 4,746 inputs for January 1895-October
2026. The full-cache audit and first 12-month temperature-ranking pilot are
implemented for laptop testing; full-record results and the map await user
review. SPI validation and monthly scheduling remain separate from the live
daily workflow.

November 7 monthly temperature validation: independent daily-calendar expansion
and base-R ranks passed at eight grid locations for October 2026 and an October
1993 historical contrast (128 metric checks and 1,832 window comparisons; zero
failures). This validates local arithmetic using the same PRISM inputs, not the
underlying modeled temperatures against an external dataset. See the
[monthly guide](prism-monthly.md#independent-numerical-checks).

November 7 next local increment: 1-/3-/6-/12-month temperature and precipitation
ranking pilots share one cache audit, use per-product verified completion
markers, and write a local eight-map review gallery. Precipitation uses sums
and empirical zero/tie handling, not SPI. Full multi-period results await laptop
testing and user review; no scheduled update or publication is enabled. See
[multi-period testing](prism-monthly.md#multi-period-temperature-and-precipitation-ranking-review).

User-selected refinement: add distinct record-warm and record-wet categories
above the percentile classes, including tied maxima only with complete eligible
history at the cell. Incomplete-history cells retain supported percentiles;
constant/all-zero series are not highlighted as records. Scientific percentiles
remain separate from display codes. The next local gallery rebuild includes
these flags; production remains unchanged.

The symmetric record-cold/record-dry classes are also implemented for local
testing. Zero-total record-dry highlighting requires zero frequency <=2% across
the complete matching record; common-zero and constant histories retain their
ordinary percentile display. Tied/unique record flags and counts remain separate
from the scientific percentiles and from SPI development.

SPI-1/3/6/12 local pilots are implemented for laptop testing, using fixed
1895-2020 calendar-matched gamma-MLE fits with explicit zero mass and automatic
support/fit guards. Independent optimizer and zero-transform checks pass.
October 2026 SPI-1 smoke testing produced 47,056 valid cells and withheld 118
of the 47,174 currently valid padded-domain cells; remaining durations await
user review. Fit coefficients and successful map outputs are cached separately.
See [SPI testing and method choices](prism-monthly.md#spi-1-spi-3-spi-6-and-spi-12-local-pilots).
Calibration/fit-policy review and the external hotlink exports remain release
requirements; daily publishing and monthly scheduling are not enabled yet.

November 8: revision-aware monthly updater implemented for local testing.
Refresh the latest eight completed months during days 1–5, with explicit manual
catch-up, staged validation, resumable downloads, installation rollback and
per-cycle completion records. Rebuild only affected retained products and ensure
the latest twelve maps; reuse fixed SPI calibration fits for recent revisions.
Age-based stability is not source-confirmed final status. Next: run the local
revision test, review change/build reports, then integrate staging publication
and the monthly operational entry point. See the
[revision updater commands](prism-monthly.md#revision-aware-monthly-updater-local-testing).

November 8 local site review: Monthly Climate page added with temperature,
precipitation and SPI tabs and a shared 1-/3-/6-/12-month selector. Staging
verifies current source/policy fingerprints and copies a complete twelve-map
release. Rendered-page validation checks checksums, images, links and one
consistent ending month. Local October 2026 render passed 12/12 maps; selector
tests cover all twelve combinations. Next: user layout review, then daily-runner
integration, monthly cache transfer and VM staging. No deployment in this step.

Approved local groupings are now applied to the actual site for staging review:
temperature values/departures/ranks/freeze timing, precipitation totals/ranks/
dry spells/wet-day characteristics, and tabbed/grid Snow. Individual product URLs
remain, but the preview's Original individual pages navigation is excluded.
Monthly Climate remains above Historic Years. Generated navigation preserves
the new layout; grouped and monthly rendered-map checks now gate S3 sync.
See [staging preparation and VM commands](monthly-and-grouped-maps-staging.md).
The staging cache/SPI-fit transfer and page/layout trial are complete. The VM
verified 4,746 grids and four fits, built twelve maps in 162 seconds, and skipped
a repeated cycle with zero requests. The daily-runner hook is now implemented,
opt-in through `SWC_MONTHLY_MAPS=true`, with early-month retries, retained-release
fallback, overdue warnings and console/ntfy statistics. Offline integration
tests pass; the real-cache adapter check reused October maps without requests.
Next: enable the flag on staging and test its normal daily run, then transfer
the production seed and promote the tested integration. No second cron job is
needed. See [monthly daily integration](monthly-daily-integration.md).

Explore the monthly PRISM record proposed for **1895-present**, verifying the
actual available variables, resolution, geographic coverage and latest complete
month before adopting that period as a product label. Decide which maps benefit
from the longer record: candidates include monthly or seasonal precipitation
totals, mean temperatures, departures, rankings and percentiles. Monthly data
cannot supply daily extremes, freeze-night counts or daily spell metrics.

**Historic Years rebuild requested November 8, 2026:** prefer the monthly PRISM
dataset for completed seasonal and water-year precipitation totals, mean
temperatures, departures, rankings and SPI wherever the product can be derived
from complete monthly inputs. Reuse the monthly cache and methods to rebuild
these archive products and extend coverage toward 1895, subject to sufficient
comparison support and complete cross-year windows (the first full October–
September water year is WY1896). Decide explicitly whether historical rankings
use the full available record or only data available through that year, and
label the choice. Retain daily PRISM for extremes, freeze and spell metrics,
station observations for station histories, and SNODAS for snow; those products
cannot be reconstructed from monthly PRISM. Pilot comparable existing years
before replacing archive maps, document any method differences, then backfill
the longer record and validate the pages. This is scoped future work; no
historic maps are rebuilt in the current Monthly Climate release.

Plan a **once-monthly update**, separate from daily PRISM processing. Define the
release/completeness cutoff, preliminary-versus-final handling and a bounded
revision check; cache completed months and rebuild only affected products.
Choose reference periods and explain the difference between a fixed normal and
a full-period ranking. Pilot a small map set before attempting long-term
historical backfill.

**Scheduling requirement confirmed November 6, 2026:** the previous month's
monthly data become available during the first couple of days of the new month.
Schedule a bounded early-month availability/retry window (exact days to be
confirmed in the access pilot), rather than downloading or rebuilding monthly
products throughout the daily cycle. Record the last successfully completed
target month and skip subsequent scheduled attempts once it is complete.
Validate all required fields before advancing that marker; if inputs are not
ready, retain the previous verified maps and retry within the window. Report
an unresolved update at the end of the window. Include any bounded checks for
revisions to recent preliminary months in this same monthly run. Explicit
manual catch-up/rebuild commands may run outside the scheduled window.

**Specific deliverables requested November 2, 2026:** create a **12-month SPI
map** and a **12-month mean-temperature ranking map**, published as directly
hotlinkable images to support the
[Drought and Livestock Grazing dashboard](https://cales.arizona.edu/droughtandgrazing/dashboard.html).
The existing dashboard describes Arizona maps ending in the most recent full
month and updating at the beginning of each month. Scope Arizona-focused
exports for this use, alongside any broader SW Climate Watch versions; confirm
extent, dimensions and legend compatibility before replacing external links.

For SPI-12, validate a genuine standardized precipitation index using 12-month
accumulations, calendar-ending-month distributions, an explicit fitting/reference
period, zero-precipitation handling and adequate historical support. Coordinate
with the validated SPI workstream; a precipitation percentile or simple z-score
is not an interchangeable substitute. For temperature, define the rolling
12-month mean, month/day weighting, ranking direction, historical comparison
period, eligible windows, ties and categorical labels. Clearly distinguish
record rank, percentile and departure from normal.

Provide stable public HTTPS image URLs that retain their filenames as each new
month is published, plus dated archived images for provenance. Put the exact
12-month dates, source and reference/ranking period on each standalone image.
Verify direct embedding from the dashboard, image content type, cache refresh
behavior and replacement of the existing source attribution. Publish only after
all 12 monthly inputs qualify; retain the previous verified image if an update
fails. Define the monthly availability/revision policy rather than promising a
new image on the first day before inputs are ready. These are scoped
deliverables; no dashboard links or operational products are changed yet.

### Local storm reports and NWS watch/warning polygons

Scope querying and displaying archived **local storm reports** and **NWS watch
and warning polygons** in Daily Explorer, seasonal summaries, or both. Identify
sources, archive depth, supported hazard types and spatial coverage first.
Decide whether to use map overlays, event lists, or linked detail views.

Distinguish reported impacts from issued hazards; a warning polygon is not an
observed impact footprint. Define report occurrence versus submission time and
polygon issuance, valid and expiration times, including updates/cancellations,
UTC/local-day boundaries, duplicates and multi-day events. For seasonal counts,
choose event/report/polygon counting rules and document reporting limitations.
Use incremental cached metadata and lazy-loaded regional geometry; preserve
explicit unavailable states and avoid downloading every archive on daily runs.

### Historic seasons: station observations and Daily Explorer maps

Decide what additional station and daily-map content should appear on each
historic-season page. Candidates include station seasonal totals/temperatures,
rankings and extremes with record/coverage context; selected notable-day maps;
and links to the corresponding station or Daily Explorer view.

Coordinate this with completed-year Explorer retention and navigation. Set
season/water-year definitions, station eligibility and completeness rules,
cross-year links, archive manifests and end-of-season completion checks.
Compare retaining existing daily maps, building selected events, and producing
complete daily collections before choosing storage and backfill policies.
Keep old seasons accessible without publishing full station histories or
automatically regenerating every historic day in the normal daily workflow.

### Hydrological data and gauge conditions

Explore a regional map of gauging-station conditions with station details,
time series and links to source records. First identify suitable providers,
regional station coverage, archive access, update latency and usage constraints.
Decide whether the first version shows discharge, stage, or both, and whether
historical support permits seasonal percentiles or other condition categories.

Define instantaneous versus daily-mean timing, units, reference/sample support,
provisional/revised observations, missing or stale gauges, and interpretation
at regulated or otherwise affected sites. Show explicit limitations rather than
treating unsupported comparisons as normal conditions. Benchmark a small
station network, incremental refreshes and cached/lazy-loaded browser payloads
before integrating it into the daily publisher or historic-season pages.

### Event summaries connecting weather, precipitation and impacts

**Status: deferred by user request, October 27, 2026.** Preserve these ideas for
a later scoping session; no prototype or daily-publisher integration is planned
in the current work.

Scoping reference: [CW3E event summary, October 21-23, 2026](https://cw3e.ucsd.edu/cw3e-event-summary-21-23-october-2026/),
reviewed October 27. Its embedded figures connect 500-hPa evolution and moisture
transport with Stage IV event precipitation, precipitation as a fraction of
normal water-year precipitation, WPC rainfall reports, archived WPC/SPC outlooks,
NWS hazards and local storm reports, gauge flood categories/hydrographs, and
documented impacts. These are complementary sources with different reporting
and accumulation windows, not interchangeable observations.

Candidate bounded first prototype: select one completed Southwest event and
assemble a linked event view from existing caches, outside the daily publisher.

Preferred eventual placement is an optional **Event summary** view within Daily
Explorer, preserving existing single-day and 7-/30-day navigation. Begin with
prebuilt named events whose dates are explicitly configured, with shareable
links from historic-season pages. The browser selects among existing products;
the static site cannot run R to calculate a new map for arbitrary selected dates.
Cache completed-event outputs and invalidate them when relevant inputs or
calculation/rendering settings change, rather than rebuilding all events daily.

Keep unrestricted start/end-date summaries as a separate feasibility question:
browser calculation would require publishing compact numeric daily grids
(existing PNGs cannot be summed), with payload and responsiveness benchmarks.
An on-demand calculation service is another option but adds server operations
beyond the current static-site design. Neither option is selected for development.

1. Event-total PRISM precipitation, daily progression, station totals, and
   contribution to water-year-to-date precipitation. Separately consider event
   precipitation divided by the full normal water-year total; label this
   denominator explicitly, since it is not percent of normal for the event.
2. Link the same dates to existing 500-mb, jet and PWAT/low-level-flow maps and
   archived discussions. Daily means explain broad evolution; selected subdaily
   analyses could be a later event-only option. PWAT and 850-mb winds do not
   constitute IVT or establish an atmospheric-river classification.
3. Add event station rankings only with matched-duration/calendar definitions,
   completeness and reference/sample support. Keep rainfall rarity separate
   from fraction of annual normal and from hydrologic impact.
4. Scope a small gauge network with observed hydrographs, event peaks and
   supported flood categories, reusing the hydrology workstream. Preserve
   missing/provisional/beyond-measurement-range cautions; avoid automatic
   record claims without verified historical support.
5. Coordinate event overlays for local storm reports and issued hazard polygons
   with their existing scope. Archived WPC excessive-rainfall and SPC convective
   outlooks are optional forecast-context links, clearly separated from what
   actually occurred. Curated impact/source links can supplement automated maps.

First decisions: event dates and reporting-day conventions; fixed versus
user-selected windows; AZ/NM versus a broader Four Corners context; station and
basin summaries; ranking/reference definitions; and persistent event URLs linked
from Daily Explorer and historic seasons. Benchmark cached event sums and
payloads before integration. Stage IV/MRMS, IVT/AR diagnostics, subdaily radar
and storm animations require separate source/cost assessment; they are not
added to the routine daily downloads by this scoping entry. Existing IVT
deferral remains in effect. No new operational product is enabled here.

## Additional precipitation evolution and historical-context scope: November 1, 2026

Status November 4: cumulative station plots are live; historical-total time
series are implemented locally after Analytics; historical threshold odds remain scoping only. They connect current accumulation, historical variability
and the range of possible end-of-year outcomes.

### Station cumulative daily water-year precipitation

Implemented and live November 4; the following requirements record the design.
The interactive plot in Station Conditions/Station Explorer begins
October 1 and accumulating through the latest usable observation date. Show the
current water year against supported climatological lines (mean and/or median,
with optional historical percentile bands) and a small selection of previous
water years. Hover should show date, accumulated inches and comparison values;
allow selection of prior years without loading every full station history.

Decide which climatological lines are most useful, the reference period and
minimum sample support at each date, and whether to highlight the preceding
year, wettest/driest complete years or user-selected years. Compute a median
cumulative curve from historical cumulative totals, not by summing daily medians.
Match October-September dates consistently and define February 29 handling.
Missing/flagged precipitation must not become zero: distinguish incomplete
observed subtotals from complete totals and withhold unsupported comparisons,
consistent with existing station symbols and notes. Preserve ThreadEx/component
record distinctions and station-specific reference coverage.

Reuse cached ACIS daily histories and revision checks. Cache reference curves
and completed-year summaries; increment or revise the current-year curve only
when its inputs change. Benchmark a station-detail prototype and compact
lazy-loaded numeric series before enabling it across the network.

### Historical seasonal and water-year precipitation time series

The first water-year-total increment is implemented locally November 4. The
following scope includes later seasonal and regional extensions. Build
interactive historical-total plots inspired by Westwide Drought Tracker:
one seasonal or water-year total per year, with a normal line, optional departure
or percent-of-normal view, hover values, and a clearly marked current incomplete
season. Begin with station precipitation; separately decide which regional,
basin or PRISM grid summaries belong on map-detail and historic-season pages.

Define selectable seasons (including cool season and monsoon), year labels,
cross-calendar-year boundaries, comparison baseline and units. Show record span,
eligible-year counts and missing-year gaps; keep current season-to-date values
distinct from complete historical totals. If partial-season comparisons are
offered, compare matching dates in prior years. Treat trend fitting as a separate
choice with record/homogeneity limitations, not a default feature.

Precompute small seasonal/annual summary tables from existing station caches
and supported PRISM archives; refresh only affected years. Coordinate longer
regional records with the proposed monthly PRISM workstream rather than
expanding daily downloads back to 1895. Benchmark cached generation, browser
payloads and interaction costs before choosing the initial geographic scope.

### Historical odds of reaching water-year precipitation thresholds

Reference: [CW3E odds of normal water-year precipitation](https://cw3e.ucsd.edu/odds-of-normal-water-year-precipitation/),
methodology reviewed November 1, 2026. CW3E describes combining precipitation
already observed with historical remaining-season totals, then counting how
often the resulting full-year total reaches a target. Its published example
uses a WY1948-2017 sample and a 1981-2010 normal; choose and label our own
supported sample and baseline rather than copying those periods.

Candidate targets include 75%, 100%, 125% and 150% of full water-year mean
precipitation, with other fractions or fixed amounts considered later. Decide
whether the event is strictly above or at least the threshold; an above-average
total is not the same as an above-median total. The denominator is the full
water-year normal, not normal-to-date. Separately consider final-total quantile
or exceedance ranges as a companion to threshold probabilities.

Start with one station or small regional pilot: add the current observed total
to each eligible historical remainder after the same cutoff date and calculate
the fraction meeting each threshold. These are historical/climatological odds,
not a dynamical forecast, and they do not automatically incorporate ENSO or
forecast rainfall. Test the assumption that the remaining-season distribution
can be used regardless of rainfall already received, specifically for Southwest
cool-season/monsoon regimes; CW3E's reported California tests cannot establish
that assumption for Arizona and New Mexico. Any conditional analog/ENSO variant
needs separate sample-size and out-of-sample validation.

Define complete historical seasons, missing-data guards, sample counts,
finite-sample uncertainty, ties, and treatment of an already-reached target.
Use held-out historical years to assess reliability and baseline sensitivity;
avoid presenting an empirical zero frequency as physical impossibility.
Cache historical remainder distributions at agreed monthly or daily cutoffs;
update current totals from existing inputs. A monthly/month-end prototype is
the bounded starting option. Assess daily incremental updates, gridded maps
versus station/regional cards, reference-cache size and runtime before adding
these products to the operational daily cycle.

## New exploration: conditions synopsis and daily change summary

**November 9 status:** the deterministic template and its regional snow/evidence
follow-up are confirmed live. Earlier local-pilot and first-task descriptions
below are development history, not instructions to restart implementation.
The current scope includes supported seasonal snow context and direct dated
evidence for quantitative selected bullets. AI synthesis remains deferred.

**Active decision, November 5:** move forward with the template synopsis.
AI interpretation and an unlisted daily AI review page are deferred. The optional
API approaches below remain historical scoping notes, not scheduled work.

The [first-increment scope](conditions-synopsis-scope.md) now specifies the
evidence inventory, candidate thresholds, change accounting, local template/API
comparison and performance/release gates. It is the implementation-scoping
reference; the following preserves the broader intent of the request.

Seasonal behavior is part of the first-increment acceptance criteria: winter
snow storage/deficits, spring snow loss and transition, summer localized rain
and heat, and fall first freezes/snow plus the water-year reset. Configurable
editorial priorities retain common 30-day/water-year anchors and source quality
guards. Review representative seasonal examples and boundary behavior; calendar
changes alone must not create climate-change claims. See the scope's seasonal
priorities and transitions section.

November 4 local increment: `scripts/build-conditions-synopsis-evidence.R`
now inventories five cached PRISM grids (39 regional facts), strictly matched
station observations and snow pair/checksum availability. The local
`scripts/build-conditions-synopsis-draft.R` adds a linked HTML/Markdown template
with up to two screened station extremes, selected by seasonal priority and
complementary geography/metric family. Temperature and freeze departures are
included alongside daily/three-day rainfall. Local wording/seasonal review,
regional snow interpretation, published-snapshot change accounting and
publication integration remain pending; historical extreme ranks and hot/warm
threshold-count highlights remain separate adapters. These scripts write only
diagnostic review artifacts and make no requests or publication changes.

The subsequent local increment leads with seven-day conditions, then 30-day and
water-year context as bullets. Cached daily grids supply recent rainfall,
temperature and notable-day coverage; matching seven-day station details supply
extremes. Freeze-night departures remain seasonal. A separate local-preview
history exercises event novelty, stable reruns, supported material changes and
quiet-day wording without advancing a published snapshot. Production comparison
hooks, regional snow interpretation and seasonal review are still pending.

The next local refinement adds readable narrative dates and direct station
extreme ranks/anomalies from complete matching windows in the cached full
record. Focus now responds to rainfall, heat/cold, mixed and quieter-week
signals; unusual dry spells and seasonal departures provide longer-term
fallbacks. New-date historical processing took about one minute on the laptop,
while unchanged cached previews took about 4–5 seconds. Benchmark on the VM
before enabling a daily dependency. No new downloads or impact claims are made.

Requested November 4, 2026 while the production release was running. Planning
only: no new page, API request or daily-workflow dependency is enabled here.
Consider a Home **Maps / Synopsis** tab, with a directly linkable synopsis page
for sharing and accessibility. Keep the map dashboard as the initial view until
a local layout trial is approved. The synopsis should help visitors interpret
conditions and find the relevant maps, stations and Explorer dates.

### Content and evidence

- **Past 30 days:** rainfall amount/coverage, dry/wet percentile-area patterns,
  temperature departures and supported notable days. Identify spatial contrasts
  across AZ/NM, not just a combined regional mean. Reuse existing regional
  summaries and add only a small agreed set of cached state/subregional metrics.
- **Water year to date:** precipitation totals and supported comparisons,
  station accumulation and freeze-night context, plus seasonal snow storage
  and seven-day change when meaningful. Retain each variable's actual period,
  baseline, geographic coverage, units and data-through date.
- **What changed:** a short, prioritized set of changes since the **last
  successfully published** evidence snapshot. Distinguish newly observed days,
  revisions to older source data, rolling-window days entering/leaving, and
  actual condition changes. A failed publish must not advance this comparison
  anchor; a rerun with identical facts should not claim a new event.
- **Notable observations and where to look:** eligible station extremes,
  changes in spatial coverage or large supported departures, with links to
  existing product pages, station views, Explorer dates and discussions where
  valid links are available. Scope new deep-link support if necessary rather
  than inventing selector URLs that the tools do not support.

Build a compact, versioned numeric evidence file after data validation. Each
fact needs an ID, source/product, period/end date, geography, reference/sample
support, quality status and approved link. Apply explicit, configurable
thresholds for salience, geographic extent and publication-to-publication
change. Favor a small number of meaningful highlights; do not manufacture a
daily narrative change from unchanged data or noisy single-pixel maxima.
Avoid double-counting overlapping ThreadEx and fixed-station records as
independent evidence. Incomplete station precipitation remains a lower bound;
unsupported comparisons and low-median snow ratios remain withheld.

CORe circulation/PWAT may provide descriptive context, but absolute height or
moisture maps cannot support an anomaly claim without a validated baseline.
Weather UTC means, PRISM reporting days, SNODAS snapshots and station dates
are not interchangeable. Attribute any discussion-based interpretation to
its dated NWS/WPC source. Do not infer ENSO causation, flood impacts or drought
classification from spatial coincidence or a single index value.

### Rendering options and proposed sequence

1. **Template baseline:** generate concise linked sentences from validated
   evidence and deterministic highlight rules. This is reproducible, requires
   no AI calls, and provides an operational fallback. The page remains static
   HTML published to S3 even though its content is regenerated daily.
2. **Optional AI-assisted synthesis:** send the compact curated evidence, not
   whole rasters, full histories or screenshots, to the OpenAI API. Request a
   short structured response containing a headline, period summaries,
   change highlights, limitations and supporting fact IDs. Let local code
   supply numeric values, dates and approved links where practical. Test
   whether this improves synthesis and explanation enough to justify it.
3. **Validation and release:** check returned structure, fact references,
   dates/numbers/units and unsupported-record/causal wording. Structured
   Outputs constrains response shape, not scientific accuracy. Compare
   template and AI drafts on wet/dry/mixed periods, sparse or lagged data,
   early water year, source revisions and unchanged reruns before release.
   Require evidence checks; do not assume automated prose validation can
   establish every interpretive claim.

Cache the evidence and generated text by input/prompt/model version. Reuse
unchanged results and regenerate only after materially changed approved facts;
benchmark evidence extraction separately from API latency and cost. Use a
bounded timeout/retry and output-length limit. API failure or invalid output
must fall back to the current deterministic summary without blocking map/site
publication. Any retained older narrative must be visibly dated and cannot
appear to describe new inputs. Keep API credentials on the VM, record usage
and generation metadata, and label AI-assisted prose if that option is adopted.

First bounded task: agree the evidence fields and 5–10 highlight rules, then
produce a local template-based synopsis for several cached dates. Review that
before selecting a model, acquiring credentials or enabling external calls.
Model choice, actual daily cost, account settings and latency remain to be
measured; no API budget or pricing estimate is assumed in this scope.

References for the optional API route: official OpenAI
[Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
and [production guidance](https://developers.openai.com/api/docs/guides/production-best-practices).

## Suggested sequence

Follow the [priority order above](#priority-order-and-working-sequence).
Station seasonal histories, daily chart/CSV/layout enhancements and monthly
climatology are now confirmed in production. The next recommended increment is
a local seven-day 500-mb/PWAT means pilot using cached CORe fields; completeness
and runtime/cache checks precede any 30-day expansion or operational integration.
Historic snow anomalies follow, with regional climatology and remaining station
extensions retained for later scoping. External dashboard embedding/Arizona-only
exports remain separate. Heat metrics stay deferred until spring 2027; AI
synthesis remains deferred. Move one bounded increment through local review,
staging and explicit promotion before adding another daily dependency.

Keep the operational daily publisher stable while experiments run locally.
Retain the VM staging cache for development. The earlier report of 192 GB free
on /home is historical; check current usage before making cleanup decisions.

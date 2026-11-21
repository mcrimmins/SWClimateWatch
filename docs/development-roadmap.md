# Development roadmap

Planning review: November 18, 2026. This is the consolidated backlog, not a
commitment to enable every candidate product. No production settings change
when this document is edited.

## Collaboration and scope guardrails

Agreed November 6, 2026: use this document as the shared project roadmap and
the continuing roadmap conversation for new ideas, scoping and prioritization.
Update this roadmap only with decisions explicitly agreed with the user.
Monthly PRISM development is underway in a separate conversation; do not modify
its implementation files as part of roadmap planning.

## Operational baseline

November 18 repository baseline: [PR #1](https://github.com/mcrimmins/SWClimateWatch/pull/1)
merged `codex/daily-explorer` into `main` with merge commit
`e1deb03681f286f7f6a7c7b5eac60a3ddc729ec6`. The laptop now uses that `main`;
both VM checkouts are pinned to the same commit. The merge and checkout
transition are complete. This did not publish the site or change the daily cron.
The next scheduled production run remains a separate operational confirmation.

November 13 operational review: the station update, monthly manifest and browser
freshness repairs are complete in production. The scheduled daily run succeeded;
see the completion evidence below. Continue routine source/cache monitoring.

November 15 production confirmation: the PRISM comparison code-review fixes
have completed local review, staging, production cache rebuilds and publication.
No further promotion step remains for this increment.

November 17 production confirmation: the user confirmed promotion of Interactive
Maps and automatic refresh at release `1c23270adfe1f17e47ff7f0cb9a4519f20a87f56`,
after a successful full staging daily run and final layout review. No promotion
remains for this feature. Confirm the first subsequent scheduled production
refresh and next automatic monthly rollover separately; no new production
run timing or source-coverage report was supplied today.

November 17 raster plotting completion: the user confirmed staging and production
review of release `d00e5b9794a22cbf4c69222a913f31bccf00a2fe`. Freeze-free season
length and departure PNGs were promoted with the shared native-cell geometry
fix and cached-only rebuild tools. No rendering-fix promotion remains. Monitor
the next scheduled run for plotting warnings; no new production timing or
warning-count log was supplied with this confirmation.

The user confirmed the November 4 morning production run published release
`e4ec458d049417e567ba182eb824d4070b8d4e0e`. Production runs daily on the AWS VM;
the laptop remains the development environment, with a separate VM staging
checkout and S3 prefix for testing releases.

Live features include:

- Native-cell plotting for sparse/missing-axis grids, confirmed in production
  November 17. Freeze-free season length and departure maps were rebuilt from
  cached derived grids. Dense grids retain the raster fast path; numerical
  values, masks and comparison caches are unchanged.

- Interactive Maps, production confirmed November 17: 39 Current Conditions
  choices, seven Daily History views over 30 retained days and 28 Monthly Climate
  choices. Linked selectors, native-cell point tables, basemaps/roads and a
  full-screen view are live. Daily/site-only publication refreshes cached inputs;
  monthly data follow the accepted release and revisions. Matching-cache
  retention and checks before upload protect incomplete refreshes. Guidance is
  collapsed below the map; the redundant monthly shortcut is removed.

- Climate of the Region, confirmed in production November 15: all 39 fixed
  1991–2020 reference maps, topic tabs, seasonal comparisons, cached publication
  checks and stable catalog links. No new daily downloads or climatology rebuilds.
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
  are published, including seasonal peak-SWE departure and percent-of-median
  companions for WY2005-WY2025, confirmed in production November 14.
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

### November 13 operational repairs - production verified

The November 13 scheduled production run published successfully in **36m 12s**
(runner elapsed 2,173 seconds; exit 0). It validated **54/54 current and 352/352
historic maps**. These results close the three operational fixes:

- **Station update - complete:** the station module-loading repair is deployed.
  The full daily run reported `Stations: updated; 62 records (51 mapped)`,
  replacing the earlier subscript-out-of-bounds failure and retained-page fallback.
- **Monthly manifest warning - complete:** the missing-release manifest guard
  and cached-release reconciliation are deployed. The full run emitted no monthly
  manifest connection warning; October's completed cycle used no new requests
  and took about one second. This does not test December's new monthly cycle.
- **Browser caching - complete:** staging and production site-only publication
  completed the one-time cache-policy upgrade. Staged/rendered asset checks passed
  for two Explorer and nine Station assets. Production HTTP verification returned
  200 and `Cache-Control: no-cache,max-age=0,must-revalidate`. Content-versioned
  app scripts/styles and future publication headers are automatic; stable map
  hotlinks retain their five-minute policy. Already-open tabs still need a reload.

PRISM reached November 12 (24 changed/processed inputs); snow reached November 13
(one new daily grid). Explorer reused 70 dates and rebuilt three, for 73 dates/
511 maps. Weather retained 72/73 Explorer dates and 29/30 recent dates, latest
November 11, with one failed/pending date queued for automatic retry and no
withheld or unknown wind overlays. Means reached 28 periods/84 maps, with six
built, 22 reused, 32 deferred and zero unavailable (56 seconds). The deferred
mean backlog remains bounded catch-up work, not a completed full-archive build.

Remaining maintenance: monitor the CORe retry/mean queues, address repeated
raster-rendering warnings as a separate geometry-only fix, confirm GA4 Realtime,
and verify the December 1-5 monthly cycle. No additional cron or production
configuration change is required for the three completed repairs. The release
hash and detailed station-reference cache statistics were not provided with
this run; do not infer them from laptop HEAD.

### November 14 historical seasonal snow anomalies - production complete

The user accepted the expanded local archive and VM staging site, then supplied
successful production publication output. The site-only run finished in
**4m 44s**, validating **54/54 current and 352/352 historic PRISM maps**. The
dedicated rendered snow check returned **PASS: 21 years, 84 snow maps, 42 anomaly
companions and zero failures**. Feature delivery and production promotion are
complete; the exact final release hash was not supplied with this confirmation.

Historic Years WY2005-WY2025 now include peak SWE, snow-covered days, peak-SWE
departure from median and peak-SWE percent of median. Comparisons use the
screened WY2005-WY2025 seasonal peaks, at least 18 eligible reference years and
95% daily coverage per eligible year. Percentages require a median peak of at
least 1 inch. Departure gray/white distinctions, unavailable cells, documented
peak masks and existing archive review cautions are retained. These compare
seasonal peaks, not the same calendar date or accumulated snowfall.

Publication restores verified cached maps/page sections after checkout or page
regeneration and checks source/rendered integrity before upload. The explicit
archive build is resumable and reuses completed years; the daily publisher does
not recalculate historical anomalies or download more SNODAS daily data. Stable
dated image paths and catalog entries are included. See the
[archive release guide](snodas-seasonal-anomaly-release.md).

The same production report showed weather coverage at **28/30 recent dates and
72/74 Explorer dates**, with no withheld wind overlays. These are remaining
source gaps to monitor through the existing retry mechanism, not snow-release
validation failures. This was a site-only publication, not a new measurement of
the full daily update or station refresh.

### November 15 PRISM comparison fixes: complete in production

The user confirmed the production release after successful staging review and
the production cache rebuild/publication steps. Completed changes include:

- Water-year maximum three-day precipitation ranks now compare matching
  October 1–calendar-date windows, with separately versioned, validated caches.
- Freeze comparisons distinguish verified no-freeze seasons from missing data;
  revised reference caches preserve event-frequency and coverage safeguards.
- Spring last-freeze departures have provisional-season guards. Overdue first
  freezes have separate delay lower bounds without inventing observed dates.
- Freeze category boundaries, leap-calendar display and configured reference
  labels are corrected; tied-zero precipitation ranks have clearer explanations.

Targeted regression tests and synthetic visual reviews preceded staging and
production review. Monitor subsequent daily runs for cache reuse and seasonal
freeze behavior. The optional higher minimum wet-day count for intensity ranks
remains deferred pending a coverage/runtime assessment; the current minimum and
percentile algorithm are unchanged. See [assessment and cache migration notes](prism-code-review-fixes.md).

### November 17 Interactive Snow and automatic updates - production complete

The user confirmed the corrected release in staging and production, including
the publication-order fix at `bf159b6`. Current Conditions in Interactive Maps
now includes observed SWE, departure from median, supported percent of median
and exact seven-day net SWE change. Zero observed SWE is transparent and remains
0.00 inches in point tables; low typical snow, unsupported references and missing
data remain distinct. The historical pilot example is not in operational builds.

The shared daily/site-only workflow follows the verified Current Snow release,
reuses unchanged bundles, invalidates them on date/source/endpoint revisions,
and reconciles reset generated pages through the normal cached Snow quality
gate. A new season without a verified snapshot waits rather than substituting
the prior season. No new cron entry or cache transfer is required.

The initial grouped-Snow checksum failure stopped upload safely. Snow is now
reconciled before catalogs, synopsis and grouped pages record image hashes;
all validation guards remain enabled. Corrected staging publication completed
in 7m 06s; production completed in 7m 08s. Production evidence:

- 54/54 current and 352/352 historic maps passed validation.
- Source and rendered viewer checks passed for the November 17, 2026 Snow
  release, with seven-day change available: 180 assets, 109,252,882 bytes.
- Snow workflow reported `READY`, one snapshot and four metrics, in 7.766 seconds.
- Production's separate weather check retained one missing CORe date:
  29/30 recent and 76/77 Explorer dates, with no wind overlays withheld.

Snow viewer integration, automatic updates and the ordering correction are
complete; no promotion remains. Confirm the next scheduled production run's
`Interactive Snow: ready/reused` line and date separately. Continue monitoring
weather retries, monthly rollover and mobile memory/network performance. See
the [completed release and operational guide](interactive-map-snow-daily.md).

### November 18 merge into main and VM transition - complete

PR #1 preserved the feature history with a merge commit: 48 reviewed feature
commits, 503 changed files, and no competing main-side changes. The reviewed
head `72bb3bb` and merged `main` have identical tracked file contents. Review
corrected one obsolete synopsis publication-order test assertion; no production
code needed changing during review.

Clean-source verification passed 3,878 R assertions across 143 test files with
zero failures, errors or test warnings. Eighteen JavaScript suites passed,
including native PRISM/Snow payload checks; syntax checks passed for 481 R
files, 19 JavaScript files and six shell scripts. One live RCC-ACIS integration
test and one optional generated weather-preview check were skipped. There is
no tracked GitHub Actions workflow; these are local checks, not CI results.

The laptop fast-forward completed after a transient Git index lock cleared.
Generated page edits are saved in stashes; untracked experiments and cached
data were preserved. Staging and production VM checkouts then moved to
`e1deb03681f286f7f6a7c7b5eac60a3ddc729ec6`. Both runner readiness checks
finished with exit 0 on November 18, with the correct separate destinations,
required packages/tools and seed assets. Production's "Local staging preflight:
INCOMPLETE" label reflects its live destination, not a failed dependency check.
AWS permissions, machine capacity and a new full publication were not tested by
those readiness checks.

No merge/promotion task remains for this baseline. Keep VM releases pinned and
use new `codex/...` branches from updated `main` for subsequent increments.
Record the next scheduled production result separately; GA4 Realtime, source
freshness/retries and the December 1-5 monthly rollover remain follow-ups.

## Priority order and working sequence

This is the proposed working order, with one feature increment active at a time.
It preserves all backlog items below; priority is not a commitment to deliver
every candidate. A deadline for the external monthly-map deliverable would move
that work ahead of discretionary features.

| Priority | Work | Next bounded step and completion evidence |
| --- | --- | --- |
| P0 — ongoing operations | Monitor the confirmed production release | Interactive Maps, automatic Snow viewer refresh, its publication-order correction and raster plotting fixes are confirmed in production November 17. Confirm the next scheduled Snow refresh/date/cache reuse; monitor plotting warnings, accepted monthly releases and weather retries/freshness. GA4 Realtime and the first automatic December monthly cycle still need confirmation. Earlier timing/coverage figures are historical snapshots. |
| Complete — monitor | Merge into main and align laptop/VM checkouts | PR #1 merged November 18 at `e1deb036`; laptop `main` and both pinned VM checkouts match. Reviewed source passed 3,878 R assertions and 18 JavaScript suites; both VM readiness checks exited 0. No new publication occurred. Confirm the next scheduled production run separately. |
| P1 — earlier-year staging testing | Historic Years from monthly PRISM | The user accepted all 86 WY1896-WY1981 pages locally after numeric/rendered PASS: 1,806 monthly maps, explicit availability notes and no unverified ENSO labels. Separate portable export and cached combined navigation/publication checks are prepared for staging; the full site will cover 130 years and 2,730 monthly maps, preserving existing daily/Snow detail. Staging review remains pending. See [staging commands](historic-monthly-backfill-staging.md). |
| P2 — recommended, pending selection | Operational and viewer performance | Profile consecutive new-date runs and outstanding phone/throttled-network targets before changing cadence, payloads or architecture. |
| Complete — monitor | Interactive Snow viewer and automatic updates | User confirmed corrected staging and production November 17, including ordering fix `bf159b6`. Four Snow metrics follow the verified Current Snow release, preserve native cells/masks and transparent zero SWE, and refresh automatically in daily/site-only publication. Source/rendered checks passed for November 17 with seven-day change available; 54 current and 352 historic maps passed. Confirm the next scheduled run separately. See [release evidence and workflow](interactive-map-snow-daily.md). |
| Complete — monitor | Raster plotting geometry fixes | User confirmed staging and production November 17 at `d00e5b9794a22cbf4c69222a913f31bccf00a2fe`. Native-size tiles protect sparse/singleton axes; dense maps retain the fast path. The two freeze-free products were rebuilt from cached grids. Local 63-field audit, seven-pair comparison and geometry/current/freeze/snow regression checks passed. No statistical-cache migration. See [findings and rebuild guide](raster-plot-geometry.md). |
| Complete — monitor | PRISM comparison code-review fixes | User confirmed production November 15 after staging and cache rebuilds. Matched-date maximum ranks, freeze support/season guards, overdue lower bounds, category boundaries and configured labels are live. Monitor cache reuse and freeze-season behavior; a higher wet-day-intensity minimum remains optional. See [assessment](prism-code-review-fixes.md). |
| Complete — monitor | Station loader, monthly manifest and browser freshness repairs | Production publication/header checks and the November 13 scheduled run close all three fixes. Retain automatic cache-policy handling, release reconciliation and station-loading regression checks. |
| Complete — monitor | Template conditions synopsis | Seasonal snow narrative, dated supporting evidence and matching weekly-temperature maps are confirmed live November 9. Retain seasonal tests, reference/coverage guards and successful-publication comparisons. AI and the daily AI page remain deferred. See [scope](conditions-synopsis-scope.md). |
| Complete — monitor | Stable URLs for all published map images | User confirmed production promotion November 10. Predictable latest endpoints, dated links, searchable HTML/CSV/JSON catalog and publication integrity checks are live. External project embedding and any Arizona-only export remain separate follow-ups. See [contract](map-hotlinks.md). |
| Complete — monitor | Station seasonal precipitation histories | Water-year, cool-season and monsoon comparisons are confirmed live. Retain completeness guards, matching-date comparisons and the hatched incomplete current-season bar. Regional historical maps remain separate. |
| Complete — monitor | Recent-period weather means and automatic retries | User confirmed production November 12: 7-/30-day 500-mb heights, 250-mb jet/flow and PWAT overlays; daily integration, cached reuse, revision invalidation, persistent CORe/mean retries and reporting. Weather anomaly baselines remain separate. |
| Complete — monitor | Historic seasonal snow anomalies | Production confirmed November 14: 21 years/84 snow maps, including 42 anomaly companions, passed rendered checks. Cached staging, resumable archive builds, reference/support guards and stable dated catalog links are live. No daily historical recalculation or new SNODAS downloads. |
| Complete — monitor | Station daily-chart normals, records and interactions | Daily normals/records were confirmed live November 10. Linked chart dates, selected-period CSV exports and the seasonal disclosure/layout refinements are also confirmed in production November 12. Retain coverage and source-record safeguards. |
| Complete — monitor | Monthly station climatology | Confirmed production November 12: 1991-2020/full-record selection, monthly distributions/extreme years, linked tables, coverage and calendar/water-year ordering. Daily annual-cycle climatology views remain optional future extensions. |
| Complete — monitor | Climate of the Region page and 39 maps | User confirmed production November 15 after local and VM staging review. Precipitation, Temperature and Seasonal comparison tabs; shared periods, selected/all-metric views and seasonal total/share choice. Fixed 1991–2020 references, portable cached publication, rendered validation and 39 stable catalog links are live. No new daily downloads or recalculation; historical extremes remain separate. |
| Deferred until spring 2027 | Station heat metrics | Scope station-appropriate temperature thresholds, counts and departures; reuse existing hot-day/warm-night screening. No implementation before spring 2027. |
| Alongside increments | Operational maintenance | Track freshness and source revisions, station audit age, raster warnings and measured cache/runtime behavior. Address specific failures promptly; schedule broader profiling as its own bounded task. |
| Later — scope before building | New sources and statistical extensions | Local storm reports/hazard polygons, gauge conditions, historical odds, completed-year Explorer/historic-season integration, custom station dates, ENSO composites and further SPI products. Each needs its own source/method/performance assessment. |
| Complete — monitor | Interactive Maps and automatic refresh | Initial production release confirmed November 17 at `1c23270adfe1f17e47ff7f0cb9a4519f20a87f56`; the completed Snow extension brings the current choices to 43, alongside seven daily views, 28 monthly choices, linked point tables and automatic cached publication. Scheduled-run confirmation, monthly rollover and phone/throttled-network performance verification remain follow-ups. See [initial workflow](interactive-map-staging.md) and [Snow extension](interactive-map-snow-daily.md). |
| Later — polish | Consistency and optional interactions | Shared city-label styling, historic RONI labels at the next archive refresh, custom Analytics events and remaining documentation reconciliation. |

November 18 status: PR #1 is merged; laptop and both VM checkouts match the
reviewed main baseline and VM readiness checks passed. Interactive Maps,
automatic Snow refresh, the grouped-Snow publication-order correction and the
final layout are confirmed in production.
No promotion remains for these or the previously
completed station, weather, snow, regional climate and PRISM comparison releases.
Observe subsequent scheduled-run behavior and monthly rollover separately.
Heat metrics remain deferred until spring 2027; AI remains deferred. External
dashboard embedding/Arizona-only exports and GA4 Realtime remain follow-ups.

### Next increments — recommendations pending selection

**Raster plotting fixes are complete in production.** The user accepted local,
staging and production review November 17 at
`d00e5b9794a22cbf4c69222a913f31bccf00a2fe`. The shared helper uses native-size
tiles for sparse/singleton axes and the raster fast path for dense grids. The
local 63-field audit eliminated six raw shared-helper warnings; first/last-freeze
maps already had explicit geometry. Freeze-free length and its departure were
rebuilt from cached derived grids for publication. Seven before/after pairs
included pixel-identical dense controls and a synthetic silent-spacing failure.
Numerical grids, masks, references and comparison caches are unchanged. No
release step remains. Observe the next scheduled run separately. See
[findings and rebuild guide](raster-plot-geometry.md).

The Snow viewer and automatic workflow are complete in production as recorded
above. The user approved the bounded monthly archive pilot November 18; its
scope is recorded below. Archive replacement/backfill and the performance
proposal remain separate decisions:

1. **Historic Years from monthly PRISM:** a larger separate increment. Pilot
   comparable existing years, choose/label historical ranking samples and review
   differences before replacing archive maps or extending the record. Start
   with three contrasting existing water years and precipitation totals plus
   day-weighted mean temperature from complete monthly inputs, using the fixed
   1991-2020 normal for departures. Compare against the current archive and
   document differences in inputs, coverage and methods; exact agreement is
   not assumed. Select the ranking sample explicitly before adding ranks.
   Keep pilot outputs isolated; archive replacement, long-record backfill
   and daily-runner integration require separate review.
2. **Operational performance:** profile consecutive daily runs and outstanding
   viewer mobile/network targets, using measured cache/runtime/payload evidence
   before changing product cadence or delivery architecture.

**November 18 approved local Historic Years pilot:** use WY2002, WY2005 and
WY2020 as contrasting review examples. Each year has precipitation total,
precipitation percentile rank, mean temperature, temperature departure and
temperature percentile rank for October-September, October-March, April-June
spring and July-September monsoon, plus September SPI-12. The user approved
the spring addition and revised monsoon window so the three seasons cover
all twelve months without gaps or overlaps; the monsoon window differs from
June 15-September 30. This changes only the Historic Years pilot definitions,
not existing station or operational seasonal products.
That is 21 maps per year and 63 maps overall. Retrospective ranks use the common
complete-water-year record from WY1896 through the latest completed September,
including later years when describing historical targets. Temperature departures
use matching 1991-2020 seasons; SPI retains the existing fixed calibration and
support/fit guards. Preserve tied-record and common-zero precipitation safeguards.

The isolated builder `scripts/build-historic-monthly-pilot.R` uses verified
monthly caches without downloading or writing shared SPI fits. Its diagnostic
reference windows and checksummed outputs are resumable. The local gallery
compares years with linked period/metric controls; September SPI is restricted
to Water year. Cached daily-derived precipitation totals, where present, provide
a separate numerical comparison report. Existing daily ranks have a different
reference record and high/low temperature departures are different metrics;
do not require identical results or replace them silently. Review via
`scripts/check-historic-monthly-pilot.R` and
`scripts/preview-historic-monthly-pilot.R` before any site integration.

Initial local verification November 18, before the spring/monsoon revision:
all 48 products built and passed saved-grid
rank/departure/SPI, mask, source and output-checksum validation. An unchanged
rerun reused all 48 maps and all three reference-window caches with zero requests.
Twenty-three focused R assertions and 84 selector combinations passed, with
browser review of SPI period switching/restoration and single-year filtering.
All 396 existing PRISM archive page/image files remained byte-identical. The
six comparable precipitation-total grids had mean absolute monthly-versus-daily
cell differences of about 0.0003-0.0013 inches; this is diagnostic agreement,
not a rule permitting automatic replacement. The user accepted that initial
visual review, then selected April-June spring and July-September monsoon.
The expanded 63-map pilot requires renewed local review. No operational page,
catalog, update workflow or deployment is changed. Updated checks enforce
the four periods, all 21 products per year, and reconstruction of full-year
precipitation and day-weighted mean temperature from the three seasons.

Expanded local verification November 18: all 63 maps built with zero requests
and passed rank/departure/SPI, mask, window, gallery and checksum checks. Seasonal
precipitation sums and actual-day-weighted temperatures reconstruct each full
water year, including leap-year handling. Twenty-six focused R assertions and
112 selector combinations passed. All 396 existing archive page/image files
remain byte-identical. The 63-map gallery is ready for user review; no existing
maps or pages have been replaced.

Local precipitation display refinement: retain the same total-precipitation
breaks and range, but anchor each intended colour to its category midpoint.
This prevents unequal low-amount bins from collapsing toward white; the first
five classes have stronger, decreasing-lightness separation. The 63-map pilot
was refreshed with no downloads, and all 15 numeric TIFFs remained byte-identical.
A regression check covers actual class-midpoint colour mapping and low-bin
contrast; the focused R tests now pass 31 assertions.

Local page integration November 18: the user accepted the maps and selected
an isolated three-page layout review before replacing the archive. Run
`scripts/build-historic-monthly-site-preview.R`, then
`scripts/preview-historic-monthly-pages.R`. The separate Quarto project lives
under `data/diagnostics/historic-monthly-site-preview`; the main site sources
and `site/_site` are unchanged. Its sidebar links the three pilot years, with
Water year / Cool season / Spring / Monsoon tabs and precipitation rank plus
temperature departure leading each period. Methods, retained daily-derived
October-March detail and Snow open as grouped sections below; WY2002 has an
explicit Snow-availability note. Historical RONI values/periods/source links are
preserved with the agreed magnitude/range-condition wording, not current CPC
official-status claims.

Verification: 45 focused page-assembly/preservation/checksum assertions passed;
all three rendered pages passed with 63 monthly maps, 12 retained daily-detail
maps and eight Snow maps. Browser checks covered period tabs, section expansion,
year navigation and image loading. All 396 original PRISM archive page/image
files remain byte-identical. No archive replacement, production navigation,
catalog or scheduled-workflow change is enabled by this local layout preview.

**Full existing-year local expansion selected:** discover the existing
`site/pages/archive/wy*.qmd` years rather than hard-coding a new archive span.
The current set is WY1982-WY2025: 44 pages, 21 monthly maps each (924), with
176 retained daily-derived detail maps and 84 available Snow maps. Build maps
with `scripts/build-historic-monthly-archive.R`, build/render the separate site
with `scripts/build-historic-monthly-archive-pages.R`, then run
`scripts/check-historic-monthly-archive.R` and open
`scripts/preview-historic-monthly-archive.R`. Outputs live in separate
`data/diagnostics/historic-monthly-archive` and `historic-monthly-archive-site`
folders; original archive pages/maps and the approved three-year preview remain
unchanged. The larger review sidebar groups years by decade.

Map batches checkpoint each year/period and hold an output-folder lock. Matching
pilot references, fits and approved maps can seed the new folder only after
signature/checksum verification, with cached paths rewritten to the new location.
Numeric checks also checkpoint verified input/output signatures; repeated checks
still verify source/output integrity, season partition and exact year coverage.
A partial year set cannot pass the all-existing-years validation gate. This is
manual local expansion, not a new daily-workflow dependency or download cycle.

Tooling verification: all 44 source pages passed content preservation and
idempotent page assembly tests, including historical RONI wording, daily-detail
cards and available Snow sections. A separate four-year end-to-end smoke test
added WY1982 to the three accepted years: 84 maps, 21 built and 63 reused, zero
requests. Its four rendered pages passed with 16 daily-detail and eight Snow
maps; unchanged numeric checks were reused on a second validation. All 396
original PRISM archive page/image files remained unchanged. The complete local
run subsequently passed: 44 years, 924 monthly maps (861 built, 63 reused),
zero requests; numeric validation PASS and rendered validation PASS with all
176 daily-detail and 84 Snow maps. The user accepted the local pages November 18.
Staging uses a separate portable publication bundle, with final map footers,
relative paths, exact year/product/date coverage and PNG checksums. Cached
reconciliation preserves the VM's Snow sections; monthly publication checks
run before S3 upload. Production promotion remains pending staging review.

November 13 local snow increment: the reviewed three-year anomaly maps now have
an isolated full Historic Years page preview with four snow cards, original
PRISM content, explicit peak/reference/display explanations and source/output
integrity gates. See [local review commands](snodas-historic-anomaly-preview.md).
The user accepted the local three-year page review. The next local increment
expands to WY2005-WY2025 (42 companions), removes pilot-only footer text in the
publication build, adds resumable/checksummed reuse, standard page staging,
dedicated publication validation and automatic dated catalog links. See
[archive build/release guide](snodas-seasonal-anomaly-release.md). Local checks
passed for all 21 years/84 snow images (42 companions), with zero rendered
failures, all 21 years reused on a second build, and 42 stable dated anomaly
catalog links validated. The user subsequently accepted the expanded local and
VM staging pages, and the November 14 production report above closes promotion.
The local-only wording here records development history, not a pending release.

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
| Historical snow anomaly companions | Complete in production November 14: WY2005-WY2025, 42 companion maps, 84 total snow images with rendered integrity checks. Preserve source/method guards, masks, cached staging and stable dated links; future source revisions/new years remain separate work. | Complete; monitor |
| Raster plotting warnings | Confirmed in production November 17: sparse/singleton cell geometry corrected; freeze-free length and departure PNGs rebuilt from cached grids. Dense controls remain pixel-identical and numerical caches unchanged. Monitor subsequent daily rendering. | Complete; monitor |
| Daily-update speed | Profile several consecutive new-date runs, cache-hit/miss behavior, costly PRISM reference work, and station processing. Benchmark before removing products or changing cadence. | Moderate |
| SNODAS source revisions | Define a bounded recheck policy for already processed archives, provenance changes, and affected reference/map invalidation. | Moderate |
| Completed-year Daily Explorer | Decide what remains public at water-year rollover, then test dated manifests, navigation, retention, storage and rebuild costs before historical backfill. | Moderate-large |
| Station metadata and additional extremes | Scope station/component history and historical extremes comparisons. Calendar-date plot records and the station climatology section are now bounded increments in the [November 6 scope](#station-and-regional-climatology-agreed-november-6-2026); heat metrics are deferred until spring 2027. Any additional formal indices need explicit periods, thresholds, completeness, ties and baseline definitions. | Variable |
| Station custom date periods | November 21: manual staging and both saved browser CSV checks passed; 62 records/5,948 annual chunks validated in staged/rendered output. Daily integration is now implemented locally behind SWC_STATION_HISTORY, with affected-year reuse, stable code-text signatures, timestamp preservation and atomic station-page retention on failure. Local daily/loader/publication tests and update/revision simulations passed. Next: full staging daily run and timings before production promotion. Physical-phone/network measurements remain separate. See station-history-daily.md. | Daily integration ready for staging run; production pending |
| Interactive raster map page (requested November 8, 2026) | Confirmed live November 17, including the Snow extension: 43 current choices, seven daily views, 28 monthly choices, native-cell queries, linked controls and automatic cached publication. Monitor scheduled production refresh/monthly rollover; measure outstanding mobile/network performance. Freeze-date extensions remain separate pilots. | Core and Snow complete; monitor |
| Shared city-label styling | Consider the smaller Daily Explorer labels for other maps; review representative precipitation, temperature and snow backgrounds before a site-wide rebuild. | Small-moderate |
| Station audit maintenance | Establish a repeatable full-record audit refresh cadence, visible audit age and automatic cautions; avoid a manual station-by-station approval requirement. | Moderate |
| Product freshness visibility | Weather activation/coverage audit is live. November 8 production reports 30/30 recent and 68/68 Explorer dates with no pending dates or withheld/unknown wind overlays, closing the earlier coverage-gap follow-up at this snapshot. Monitor recurrence; extend source-specific freshness reporting to PRISM, snow and stations later. | Small-moderate |
| Internal documentation reconciliation | Replace obsolete manual/unpublished/two-snow-map descriptions or clearly mark them as historical pilot instructions. Preserve useful reproducibility details. | Small |
| ENSO/RONI composites and analogs | Define season, variable, reference and sample membership before implementing configurable comparisons. | Large |
| Validated SPI module | Separately validate fitting, zero precipitation, reference period and SPI-1/3/6/12 behavior; do not substitute raw standardized precipitation anomalies. | Large |
| Daily weather and circulation diagnostics | Daily and 7-/30-day three-map CORe integration, retained backfill, automatic gap/mean retries and publication checks are live. Monitor source availability, queues and cache/runtime behavior. Anomaly baselines/additional fields remain separate; IVT remains deferred. | Live; monitor |
| Archived forecast discussions in Daily Explorer | Date-bound AFD/WPC links and the fixed-size embedded reader are live and user-tested. Metadata indexing and optional SPC/report sources remain future work. | Indexing effort pending |
| Long-term monthly PRISM maps | Monthly Climate rankings and SPI plus automatic revision-aware updates are live. January 1895–October 2026 inputs are verified. Stable monthly image exports and the 39-map Climate of the Region page are complete; external dashboard embedding remains unconfirmed. All 44 monthly-based Historic Years pages passed local review; staging testing is selected. | Core/reference pages live; archive replacement in staging preparation |
| Local storm reports and watch/warning polygons | Scope archived reports and NWS hazard polygons alongside Daily Explorer and/or seasonal summaries, including event-time matching, deduplication, data availability and efficient caching. | Longer-term; scope first |
| Historic-season station and Daily Explorer content | Decide which station summaries, extreme-event views and daily-map navigation belong in historic seasons; define retention, completeness and storage limits. | Longer-term; scope first |
| Hydrological observations and gauge-condition maps | Assess gauge data access, station coverage and useful streamflow/stage condition metrics, with historical context and bounded update costs. | Longer-term; scope first |
| Hydroclimate home dashboard | Dashboard layout, map-matched summaries, linked condition cards and RONI/CPC context are live. Separately scope regional cumulative precipitation versus normal with cached calculations and a runtime benchmark. | Live layout; regional evolution chart moderate |

## New exploration: interactive raster map page

**Production confirmed November 17, 2026.** The user accepted the full staging
daily run and final layout, then confirmed production promotion of
`1c23270adfe1f17e47ff7f0cb9a4519f20a87f56`. The November 15 three-product pilot
expanded to 39 Current Conditions choices, seven daily views over a retained
30-day window and 28 monthly choices. Linked selectors, native-cell point tables,
terrain/satellite/roads and full-screen viewing are live. Guidance is collapsed
below the map and the redundant monthly button is removed.

Daily/current refresh runs before unchanged-site detection. Monthly payloads
follow the verified accepted release and same-month revisions, with matching
verified-cache retention when numerical sources are incomplete. No matching
valid monthly release stops publication. Daily and site-only publishers share
this path, reuse unchanged preparation, validate assets before upload and prune
obsolete generated local viewer assets. Monthly request windows and statistical
methods are unchanged; the fixed October seed is no longer the automatic source.
See [workflow](interactive-map-staging.md).

Functional, source-cell, cache/failure, rendered and browser checks preceded
staging. The first subsequent scheduled production report and first new monthly
cycle still need observation. The original phone/throttled-network performance
targets below are not marked achieved by promotion. First/last freeze dates,
freeze-free season and snow remain separate possible extensions. The original
scope and pilot targets below are retained as history.

Requested November 8, 2026: explore a dedicated interactive map page where users
select existing map-data rasters, display them semi-transparently over a basemap,
zoom/pan and query pixel values. It must be fast and efficient within the current
project framework and complement Current Maps, Daily Explorer, Monthly Climate
and Station Conditions. Record this as feasibility work; preserve existing
commitments, the agreed climatology sequence and the spring 2027 heat deferral.
That original scope entry did not enable production behavior; the November 17
completion above supersedes the initial feasibility-only status.

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
Those prerequisites are now production-complete as of November 14; station
daily-chart and monthly-climatology increments below are also complete. The
regional climate-context page is the next recommended feature in this sequence.
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

### 3. Climate of the Region page — complete in production

The user confirmed successful production promotion on November 15, 2026,
after reviewing the local page and VM staging site. **The page and all 39 maps
are complete.** No further staging or promotion is pending for this increment.

The fixed 1991–2020 suite includes:

- Five precipitation-total maps and five mean-temperature maps: Annual and
  four calendar quarters (winter Jan-Mar, spring Apr-Jun, summer Jul-Sep,
  fall Oct-Dec).
- Four seasonal precipitation-share maps, using seasonal/annual reference
  means with matched complete support and a positive annual denominator.
- Twenty-five daily-derived maps: wet days (>=0.04 inch), pooled precipitation
  per wet day, heavy-precipitation days (>=1 inch), freeze nights (<=32 F) and
  hot days (>=90 F), each for Annual and the four quarters.

Precipitation, Temperature and Seasonal comparison tabs organize the page.
The shared period selection persists between topic tabs; Selected map / All
metrics views retain each topic's metric choice. Comparison shows four seasons
on a shared scale. The seasonal Total / Share of annual preference is preserved,
while Annual always displays totals. Notes are collapsed by default. Navigation
is below Historic Years and above About.

References require 30 complete periods separately by variable and period;
missing observations are not filled. Monthly temperatures use actual day counts
within each year/quarter and equal weighting among reference years. Wet-day
intensity pools wet-day precipitation and counts; zero wet days withhold
intensity while zero frequency counts remain valid. Thresholds, periods and
units are explicit; these are reference-climate grids, not current anomalies,
station records or local impact thresholds.

The production daily and site-only publishers restage and verify the portable
39-PNG release, validate rendered images/links and controls, and include all
39 maps in the stable catalog under `maps/latest/climate-region/`. Missing or
changed release files stop upload. The approximately 27 MiB bundle includes
source/method/checksum records; production does not need raw inputs, GeoTIFFs
or yearly calculation caches for publication. No new daily downloads or
climatology recalculation were introduced. The user confirmed the production
page after promotion; routine future-run monitoring continues.

Local verification included annual/seasonal independent comparisons, 99
calculation/layout assertions, exhaustive selector/event-wiring checks,
39-map rendered validation, portable archive round-trip verification and
publication/hotlink regression checks. Do not infer a new production runtime
benchmark from these local tests.

References: [page layout and local preview](climate-of-region-local-review.md),
[laptop/VM release commands](climate-of-region-staging.md),
[monthly reference methods](regional-climate-reference-pilot.md),
[daily reference methods](regional-daily-reference-pilot.md),
[stable image contract](map-hotlinks.md).

Optional future extensions remain separate: cool-season/monsoon regional
references, historical wettest/driest or warmest/coldest seasons, and daily
extreme distributions. Avoid duplicating annual precipitation references solely
to switch calendar-year/water-year labels: both complete cycles contain the same
twelve monthly normals. Monthly high/low temperatures are averages of daily
highs/lows and cannot establish daily records. The completed regional hot-day
reference maps do not enable the separately deferred station heat metrics.

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
Interactive Maps and automatic refresh are confirmed live November 17; no
promotion remains. The raster plotting fixes are also confirmed live November 17; no promotion
remains. Interactive Snow and automatic refresh are also confirmed complete;
PR #1 merged November 18 and both VM readiness checks passed at the main baseline.
The selected next release is the monthly-PRISM Historic Years archive for
WY1982-WY2025: local numeric/rendered validation and user review are complete;
staging testing is next. Profile operational/mobile performance
as a separate increment, and confirm the next scheduled production run.
Station seasonal histories, daily chart/CSV/layout enhancements, monthly
climatology and 7-/30-day weather means/retries are confirmed in production.
The November 13 full run closes the station/monthly/cache repair checks.
The November 14 production report closes historical seasonal snow anomalies.
Climate of the Region and all 39 maps were confirmed in production November 15,
including cached publication checks, catalog registration and stable links.
The PRISM comparison fixes are also confirmed complete in production November
15, including the cache rebuild steps; see [assessment and migration notes](prism-code-review-fixes.md). No promotion remains for either increment. Remaining
station extensions follow separately. External dashboard embedding/Arizona-only
exports remain separate. Heat metrics stay deferred until spring 2027; AI
synthesis remains deferred. Move one bounded increment through local review,
staging and explicit promotion before adding another daily dependency.

Keep the operational daily publisher stable while experiments run locally.
Retain the VM staging cache for development. The earlier report of 192 GB free
on /home is historical; check current usage before making cleanup decisions.

# Development roadmap

Planning review: October 27, 2026. This is the consolidated backlog, not a
commitment to enable every candidate product. No production settings change
when this document is edited.

## Operational baseline

The October 23 production release is commit
`55ba6a79a7a0d199302b56c5c9a7d5975e12157b`. It includes the Daily Explorer,
Station Conditions, and Current Snow's observed SWE, absolute departure,
percent of median, and exact seven-day net change when available. Historical
peak-SWE and snow-covered-day maps are published; seasonal snow anomaly
companions remain local pilots. The public Methods page reflects this release.

The reported staging run took 53m 48s with changed inputs; the subsequent
production run took 11m 40s with no PRISM or Daily Explorer rebuilds. These are
different workloads, not a controlled performance comparison. Laptop changes
must still be tested, committed, staged on the VM, and explicitly promoted.

**Current staging candidate:** Daily Explorer now includes 500-mb heights,
250-mb jet/flow, and PWAT/sea-level-pressure/850-mb-flow maps. The user reported
55 retained dates/165 maps, zero failures and zero pending. Broken NOAA indexes
were confirmed in three cases; bounded same-source pressure recovery passed on
the VM with zero-request cache checks. No weather production promotion has been
recorded. The publication coverage/activation audit has now passed on staging:
30/30 recent dates, 55/55 Explorer dates, 18 dates with recovered pressure inputs,
and no withheld or unknown overlays. The next new-date daily trial and explicit
production promotion remain pending.

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
| Recent-period weather means and anomalies (requested November 2, 2026) | Scope trailing 7- and 30-day circulation/moisture means using cached CORe fields; separately assess calendar-matched anomaly baselines, missing-day guards, interpretation and update costs. Prototype means before committing to historical baseline acquisition. | Moderate for means; larger for validated anomalies |
| Station water-year precipitation curves (requested November 1, 2026) | November 3: integrated station-detail local preview for 62 records with current cumulative precipitation, complete historical-year selection, WY1991-2020 average and middle-50% band, historical record bounds, closest progression, interactive inspection and two plot periods. Independent historical/reference caches support daily builds. Optional background curves remain a later choice. See station prototype documentation. | Integrated local review; staging next |
| Historical seasonal and water-year time series (requested November 1, 2026) | Scope Westwide Drought Tracker-style plots of historical precipitation totals, first for stations and then selected regional/PRISM summaries. Define seasons, normals, record eligibility, incomplete-year display and reusable annual-summary caches. | Moderate; regional and long-record extensions separate |
| Historical odds of reaching precipitation thresholds (requested November 1, 2026) | Pilot CW3E-style climatological probabilities of reaching fractions of full water-year normal given precipitation already observed. Validate Southwest seasonality, historical samples and uncertainty; benchmark cached historical remainder distributions before selecting monthly or daily updates and maps. | Moderate-large; methods validation first |
| Google Analytics (requested November 1, 2026) | Scope site-wide analytics for page visits and use of Daily Explorer, Station Conditions and map downloads. Confirm the Google Analytics property/measurement ID, University privacy/consent requirements, and useful events. Exclude local previews and staging from production reporting; verify on staging before enabling production. Keep browser and daily publishing overhead minimal. | Small for basic page views; moderate for custom interaction events |
| Historical snow anomaly companions | Validate seasonal peak-SWE departure and percent-of-median pilots, then stage all eligible WY2005-WY2025 years. Retain coverage and support guards and existing archive cautions. | Moderate |
| Raster plotting warnings | Locate affected builders and correct the rendering geometry without altering climate statistics. Compare before/after maps. | Small-moderate |
| Daily-update speed | Profile several consecutive new-date runs, cache-hit/miss behavior, costly PRISM reference work, and station processing. Benchmark before removing products or changing cadence. | Moderate |
| SNODAS source revisions | Define a bounded recheck policy for already processed archives, provenance changes, and affected reference/map invalidation. | Moderate |
| Completed-year Daily Explorer | Decide what remains public at water-year rollover, then test dated manifests, navigation, retention, storage and rebuild costs before historical backfill. | Moderate-large |
| Station metadata and additional extremes | Scope station/component history and historical extremes comparisons. Any additional formal indices need explicit periods, thresholds, completeness, ties and baseline definitions. | Variable |
| Station custom date periods | Assess a start/end-date selector alongside presets, initially bounded to the recent daily data already published. Separate basic summaries from historical comparisons; benchmark map/table recalculation, lazy loading, payload size and browser responsiveness before implementation. | Moderate; full historical comparisons substantially larger |
| Shared city-label styling | Consider the smaller Daily Explorer labels for other maps; review representative precipitation, temperature and snow backgrounds before a site-wide rebuild. | Small-moderate |
| Station audit maintenance | Establish a repeatable full-record audit refresh cadence, visible audit age and automatic cautions; avoid a manual station-by-station approval requirement. | Moderate |
| Product freshness visibility | Weather activation/coverage audit implemented locally, including recent/full date coverage and withheld/unknown overlays. Trial in staging; extend source-specific freshness reporting to PRISM, snow and stations later. | Small-moderate |
| Internal documentation reconciliation | Replace obsolete manual/unpublished/two-snow-map descriptions or clearly mark them as historical pilot instructions. Preserve useful reproducibility details. | Small |
| ENSO/RONI composites and analogs | Define season, variable, reference and sample membership before implementing configurable comparisons. | Large |
| Validated SPI module | Separately validate fitting, zero precipitation, reference period and SPI-1/3/6/12 behavior; do not substitute raw standardized precipitation anomalies. | Large |
| Daily weather and circulation diagnostics | Three-map CORe integration and retained backfill are in staging. Next: publication audit and next-day/cache trial, then explicit production promotion. Anomaly baselines, IVT and added weather variables remain separate. | Staging verification next |
| Archived forecast discussions in Daily Explorer | Date-bound AFD/WPC links and the fixed-size embedded reader have been implemented and user-tested. Metadata indexing and optional SPC/report sources remain future work. | Indexing effort pending |
| Long-term monthly PRISM maps | Scope selected monthly/seasonal climate products using the proposed 1895-present monthly record, with a once-monthly update cycle. Verify coverage, reference periods and source revisions before choosing maps. | Longer-term; scope first |
| Local storm reports and watch/warning polygons | Scope archived reports and NWS hazard polygons alongside Daily Explorer and/or seasonal summaries, including event-time matching, deduplication, data availability and efficient caching. | Longer-term; scope first |
| Historic-season station and Daily Explorer content | Decide which station summaries, extreme-event views and daily-map navigation belong in historic seasons; define retention, completeness and storage limits. | Longer-term; scope first |
| Hydrological observations and gauge-condition maps | Assess gauge data access, station coverage and useful streamflow/stage condition metrics, with historical context and bounded update costs. | Longer-term; scope first |
| Hydroclimate home dashboard | Local six-map refresh and tool links implemented for review; conditionally substitute supported fresh SWE for dry-spell rank. Stage after visual approval. Separately prototype cumulative precipitation versus normal, with cached regional calculations and a runtime benchmark. | Layout small; evolution chart moderate |

## New exploration: Google Analytics

Requested November 1, 2026; planning only, not enabled. Add Google Analytics
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
**Status October 27, 2026:** the original two-map feasibility pilot has advanced
to the three-map staging candidate described above. See the scope and
[daily workflow](weather-circulation-daily-workflow.md) for measured costs,
source recovery, retained backfill and the opt-in release procedure.
Requested uses include precipitation occurrence/patterns/extremes, temperature
patterns/extremes, wind events, at least a 500-mb map, subtropical jet extension
and summer monsoon-high position. Reuse the existing precipitation/temperature
products instead of creating another competing observation stream by default.

Winter/summer and recent-date pilots have been reviewed, and CORe is the selected
source for the current staging candidate. ERA5 remains a potential comparison
or historical-analysis source. IVT was deferred because of its daily overhead.
Weather climatology/anomalies and completed-year Explorer navigation remain
separate projects; this document does not enable production configuration.

### Recent-period mean weather and circulation maps

Requested November 2, 2026; scope only. Consider trailing **7- and 30-day mean
conditions**, with optional anomaly companions, to show persistent patterns
alongside the existing daily weather maps. Candidate fields are 500-mb heights,
250-mb jet/flow, PWAT, sea-level pressure and terrain-screened low-level flow.
Choose a small complementary set and decide whether period controls belong in
Daily Explorer's Weather maps panel or a separate recent-pattern view. Label
the exact UTC averaging dates and keep these periods distinct from PRISM's
observation-day windows and Daily Explorer's grid-of-days display.

First inventory which numeric CORe fields are retained and suitable for
aggregation; PNG images cannot be averaged. Reuse validated cached fields and
daily summaries where possible, with bounded recovery/backfill rather than
repeated full-period downloads. Define day/sample completeness, handling of
unavailable fields and terrain masks, and explicit insufficient-data states.
Do not silently average a shorter available subset and label it seven or
30 days. For winds, distinguish mean speed from the magnitude of the mean
vector; average vector components for a mean-flow overlay and explain that
opposing daily flows can cancel. Daily pressure-center labels should not
automatically be transferred to period means.

Anomalies need a separate, documented reference: assess the available CORe
record, a fixed climatological period, calendar matching/smoothing, leap days,
grid consistency and equal-length historical windows. Start by considering
500-mb height and PWAT departures; assess whether raw or standardized departures
are useful for each variable, with adequate sample support. Absolute heights
are not anomalies, and mean wind-speed anomalies differ from vector anomalies.
Keep ENSO/teleconnection interpretation descriptive unless separately validated.

Begin with a local two-period means pilot on representative winter and monsoon
dates. Review patterns and legends, then scope a small anomaly pilot only after
baseline feasibility is established. Benchmark one-time historical downloads,
reference storage, incremental rolling sums/means, revision invalidation and
daily rendering cost. Cache reference products and rebuild only affected windows;
do not add recurring historical baseline downloads to the production job.
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

These four ideas are recorded for future scoping, not authorized implementation
or additions to the current daily production workload. Estimate source access,
runtime, local/public storage and browser costs before selecting a pilot.

### Monthly PRISM: long-term climate record

Explore the monthly PRISM record proposed for **1895-present**, verifying the
actual available variables, resolution, geographic coverage and latest complete
month before adopting that period as a product label. Decide which maps benefit
from the longer record: candidates include monthly or seasonal precipitation
totals, mean temperatures, departures, rankings and percentiles. Monthly data
cannot supply daily extremes, freeze-night counts or daily spell metrics.

Plan a **once-monthly update**, separate from daily PRISM processing. Define the
release/completeness cutoff, preliminary-versus-final handling and a bounded
revision check; cache completed months and rebuild only affected products.
Choose reference periods and explain the difference between a fixed normal and
a full-period ranking. Pilot a small map set before attempting long-term
historical backfill.

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

These three additions are recorded for scoping, not implementation or activation
in the daily publisher. They connect current accumulation, historical variability
and the range of possible end-of-year outcomes.

### Station cumulative daily water-year precipitation

Add an interactive plot to Station Conditions/Station Explorer, beginning
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

Scope interactive historical-total plots inspired by Westwide Drought Tracker:
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

## Suggested sequence

1. Finish the weather staging audit and next-day/cache trial, then promote the
   tested commit if the user approves.
2. Return to seasonal snow companions, plotting warnings and operational
   performance as separately selected tasks.
3. Scope weather anomaly baselines and completed-year Explorer navigation
   separately; preserve the small daily download/update workload.
4. Address source revision/freshness policy and station audit maintenance.
5. Schedule larger archive, composite, station-index and SPI projects separately.

Keep the operational daily publisher stable while experiments run locally.
There is no current storage-driven reason to discard the VM staging cache:
the user's latest VM report showed 192 GB free on /home.

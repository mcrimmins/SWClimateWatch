# Daily weather and circulation maps: exploration scope

Status: **deferred at the user's request, October 25, 2026**. Retain this as a
project to start another day, not active development or a scheduled task. No
implementation, large data downloads, new public navigation or production
integration until explicitly resumed.

## Resume checklist: scope first, then implement

### Phase 1 — settle the scope

- [ ] Confirm the intended audience and diagnostic questions: daily weather,
  persistent circulation, jet extension, monsoon-high location and wind events.
  Separate pattern description from ENSO attribution.
- [ ] Agree on the minimum map set: reuse existing PRISM outcomes; start with
  500-mb heights and 250-mb winds. Decide whether surface wind and seasonal
  moisture belong in the initial release or a later increment.
- [ ] Select representative winter, monsoon, heat and wind cases for a bounded
  comparison. Check actual CORe and ERA5 field inventories and availability.
- [ ] Benchmark source latency, selective downloads, queue time, decoding,
  rendering and retained storage on the laptop and VM. Choose a primary source
  based on results, not an assumed download speed.
- [ ] Define domains/projection/dateline handling, UTC snapshots versus daily
  averages, and how dates align with PRISM reporting periods. Define sampled
  wind maxima separately from gusts and daily mean winds.
- [ ] Choose a same-source reference period and smoothing/support rules for
  anomalies. Plan one-time baseline preparation separately from routine updates.
- [ ] Agree on daily runtime and storage budgets, retention, revision checks,
  freshness thresholds and nonblocking failure behavior.
- [ ] Review sample maps and accept a written first-release specification before
  authorizing the operational implementation.

### Phase 2 — implement incrementally after scope approval

- [ ] Build an isolated local data-access pilot with bounded requests, verified
  metadata, compact caches and timing/provenance reports; no production writes.
- [ ] Implement and review the two core circulation renderers with fixed legends
  and explicit valid times. Add wind/moisture only if included in the approved scope.
- [ ] Prepare and validate only the selected baseline fields; test units,
  calendar handling, geometry, missing inputs and anomaly calculations.
- [ ] Add date-linked navigation alongside existing PRISM maps, with independent
  source dates and clear missing/stale states. Avoid duplicating current maps.
- [ ] Implement incremental refresh, bounded retries/revision detection, cache
  invalidation and measured unchanged/new-date behavior.
- [ ] Test partial days, late sources, failed downloads, corrupted caches and
  map failures without blocking core PRISM/station/snow publication.
- [ ] Update Methods and operational documentation; add publication validation
  and concise console/ntfy reporting.
- [ ] Commit and push a tested release, run the VM staging workflow, review its
  output and timings, then explicitly approve production promotion.

**First action when resumed:** review Phase 1 with the user and select a few
pilot dates. Do not start a full historical download or daily-job integration.

## Purpose

Connect the regional precipitation/temperature patterns already available in
Daily Explorer with the atmospheric setting: storm tracks, ridges/troughs,
subtropical jet extension, monsoon-high position, moisture and wind events.
Prefer a small date-linked set of maps rather than an expanding weather-model
viewer. This is retrospective diagnosis, not a forecast or warning service.

Daily patterns can be consistent with a teleconnection but do not demonstrate
that ENSO caused an individual event. Separate daily weather descriptions from
7-/30-day circulation departures, ENSO-phase composites and causal claims.

## Candidate compact map set

| Panel | Proposed variables and display | Purpose / qualification |
| --- | --- | --- |
| Existing regional weather outcomes | Reuse PRISM daily precipitation and maximum/minimum/mean temperature, their existing departures and notable-day metrics. | Diagnose rain coverage, locally heavy amounts and temperature patterns without another precipitation/temperature download. These are daily estimates, not real-time observations. |
| 500-mb circulation: essential new map | Height contours over height-departure shading; optionally sparse 500-mb wind arrows. | Locate ridges/troughs and midlevel anticyclone position. Pilot the monsoon-high depiction and avoid labeling every small closed contour as the monsoon high. Anomaly shading requires a same-dataset reference prepared separately. |
| Upper-level jet | 250-mb wind speed and sparse vectors on a broad Pacific-North America domain. | Explore jet orientation, latitude and eastward extension. A 500-mb map alone is not an adequate subtropical-jet diagnostic. Consider 200 mb for summer only after a comparison, not as another default panel. |
| Regional wind events | 10-m wind speed/direction, with a separately labeled sampled daily maximum where subdaily data are available. | Diagnose broad wind episodes. Do not call the maximum of three-hourly modeled winds a daily gust maximum or a station record. Reanalysis/ensemble-mean winds cannot resolve every local terrain or convective gust. |
| Optional moisture layer, especially summer | Precipitable water with 700-mb flow, selected instead of another always-generated map. | Explore moisture supply and monsoon circulation. Treat below-terrain pressure-level values as unavailable; decide whether 700 mb adequately represents the requested flow. IVT would be a separate, more expensive multi-level calculation. |

Start the pilot with 500-mb heights and 250-mb winds alongside existing PRISM
maps. Test wind-event usefulness before committing to a third operational map;
test moisture as an optional seasonal view. Keep absolute wind/height fields
usable even when an anomaly baseline is unavailable.

## Domains and time representation

- Circulation needs a much wider view than AZ/NM: tentatively western/central
  Pacific through North America, around 120E-60W and 10N-70N. Test dateline
  handling explicitly. Choose the smallest domain that still shows upstream
  jet extension; do not download full global multi-variable files by default.
- Regional wind/moisture views can focus on the Southwest and northern Mexico.
  Use the established regional boundaries and branding where appropriate.
- Compare a daily-mean circulation map with a fixed-time analysis on pilot
  events; neither is an instantaneous explanation for an entire day's rain.
  Every output must identify UTC valid time or averaging window and source.
- Initially link to the same available date, not the latest map from each source
  as if simultaneous. Preserve source-specific dates when one product lags.
  PRISM reporting days, station observation days and UTC reanalysis days need
  an explicit comparison policy; do not silently assert exact temporal matches.
- Daily mean wind-vector magnitude is not the mean of instantaneous wind
  speeds. Check source time-averaging definitions before labeling jet or surface
  wind maps. Sampled daily maxima require subdaily data and completeness rules.

## Dataset comparison

### NOAA CORe: first candidate to benchmark

NOAA CPC documents CORe as a 1950-present reanalysis aimed at climate monitoring,
with roughly one-day operational latency. Its cloud archive includes ensemble
means at three-hourly, daily and monthly time scales. Its design favors climate
consistency rather than the best possible short-term weather-state estimate.
This makes it a promising candidate, not evidence that it will outperform ERA5
for individual wind, precipitation or monsoon events.

Access routes to test:

- NOMADS: short rolling archive (documented as seven days), with geographic/field
  GRIB filtering. Benchmark field/level/region subsets for recent days.
- NODD cloud archive: historical and near-real-time ensemble means; select GRIB
  records with index-based byte ranges or CPC's documented get_core helper.
  This is field selection, not geographic subsetting: selected records may
  still be global and require local clipping. The archive is on Google Cloud,
  even though our production VM is on AWS.
- Do not assume all access routes offer the same temporal aggregations, levels,
  revision history or field names. Check actual file inventories and metadata.
  NOMADS snapshots and the cloud daily files may require different adapters.

### ERA5 / ERA5T: comparison and historical-analysis candidate

ECMWF documents ERA5T updates about five days behind real time, with no fixed
daily release time. Efficient downloading cannot remove that source latency.
It may be suitable if a delayed diagnostic view is acceptable, or for historical
event comparisons; it is not a same-day monitoring feed.

Test CDS requests limited to the selected dates, geographic areas, pressure
levels and variables. Use hourly data only where a sampled maximum or event
time requires it. Measure queue time separately from transfer, decoding and
rendering: a small payload alone does not establish a fast unattended update.
Label preliminary ERA5T and define a bounded revision/finalization policy.

### Selection rules

- Prefer one circulation source for routine maps and its own anomaly baseline.
  Never subtract ERA5 normals from CORe fields as though they were homogeneous.
- Keep PRISM and stations as the initial regional precipitation/temperature
  outcome products. Reanalysis rain and near-surface fields are modeled and
  must not silently replace them.
- If observed wind extremes or finer storm timing become essential, scope a
  separate higher-resolution or observational source. Do not force a broad
  climate reanalysis into an unsupported local-gust role.
- A direct operational analysis is another possible future route if same-day
  depiction becomes essential, but introduces different archive/baseline
  consistency questions. No automatic source switching in a single time series.

## Lightweight operational design to evaluate

1. Inventory before downloading. Retrieve only missing/revised dates, ensemble
   means and the agreed handful of fields/levels; no ensemble-member archive.
2. Use provided daily means when their semantics match the map. Fetch three-hourly
   data only for the wind/event products that actually need them. Avoid hourly
   multi-variable downloads just to make two daily circulation panels.
3. Clip and retain compact regional/context fields with source/time/unit hashes;
   release temporary full-domain records after verification. Keep a small
   rolling subdaily cache and a separate documented long-term retention policy.
4. Precompute the chosen calendar-day 1991-2020 circulation reference once,
   outside the daily publishing path. Select smoothing/window policy explicitly.
   Means/departures first; historical percentiles and composites are later work.
5. Cache decoded grids, regional summaries, reusable map geometry and PNGs.
   Rebuild only products affected by changed inputs or renderer settings.
6. Add bounded requests, retries, timeout and revision windows. Distinguish an
   unposted date from a corrupt payload; validate temporal completeness before
   averaging. No interpolation over missing days just to advance the date.
7. Isolate optional weather diagnostics from core PRISM/station/snow publication.
   A new map failure should produce an explicit dated unavailable/last-approved
   state and notification, not quietly serve an older map as current. Design
   and test that isolation before enabling the feature in production.
8. Aim for a small incremental daily cost: provisionally a few minutes for the
   minimal set, not tens of minutes. This is a design target, not a measured
   estimate or promise. Agree on a numerical budget after the pilot benchmark.

## First bounded pilot and decision gate

- Select a winter jet/storm case, summer monsoon-high case, regional heat case,
  and strong-wind case; use a few dates per case. No full-record backfill.
- Confirm actual 500/250-mb height/wind and 10-m wind fields, units, averaging,
  reference/valid times, ensemble treatment, longitude convention and terrain
  masks in each candidate source. Build no unsupported derived field.
- Draw paired CORe/ERA5 maps for the same dates and aggregation window, next to
  PRISM patterns. Use raw fields initially; any pilot anomaly must use its own
  documented same-source reference, not an ad hoc mixed-source climatology.
- Benchmark recent-data access separately from historical-case access on both
  laptop and VM. Record request/queue/transfer/decode/render times, bytes,
  retained storage, retries, latest available date and unchanged-run behavior.
- Review whether two circulation maps answer most questions, whether the wind
  panel adds reliable information, and whether moisture should replace it in
  summer. Test a seven-day sequence before animations or a 30-day grid.
- Only then choose the source, baseline, map suite, daily cost budget, retention,
  revision and failure policies. Develop an isolated prototype before staging.

## Primary-source references checked October 25, 2026

- [NOAA CPC CORe overview](https://www.cpc.ncep.noaa.gov/products/CORe/index.html)
- [NOAA CPC CORe archive/access comparison](https://www.cpc.ncep.noaa.gov/products/CORe/archive.html)
- [CPC selective cloud download documentation](https://ftp.cpc.ncep.noaa.gov/CORe/get_core/get_core.txt)
- [NCEP CORe product inventories](https://www.nco.ncep.noaa.gov/pmb/products/core/)
- [ECMWF ERA5 documentation and ERA5T update timing](https://confluence.ecmwf.int/pages/viewpage.action?pageId=669811810)

These sources describe availability and access, not benchmark results for our
VM. No endpoint throughput or daily runtime was measured for this planning note.

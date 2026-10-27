# Daily weather and circulation maps: exploration scope

Status: **resumed for local scoping and bounded testing, October 26, 2026**.
An isolated CORe pilot now downloads three selected fields and renders two
circulation panels. Source selection and operational integration remain pending.
The public site and daily publisher are unchanged.

Next gate: [isolated VM benchmark and transfer commands](weather-circulation-vm-test.md).
The laptop tests are complete; VM execution and timing review are pending.

## Local feasibility results: October 26, 2026

Tested winter **2023-03-01** and summer **2024-07-15** using NOAA's cloud daily
ensemble means. Each date needs one index request and three bounded byte-range
requests: 500-mb height and 250-mb U/V winds. These are individual global GRIB
records, clipped locally to 120E-60W, 10N-70N.

| Date | Index plus fields transferred | Download time | Measurement |
| --- | --- | --- | --- |
| 2023-03-01 | 229,279 bytes | 1.70 s | Forced fresh download; decoding 7.50 s; rendering disabled |
| 2024-07-15 | 224,003 bytes | 0.91 s | Fresh download in a warm R process; 11.38 s including rendering |

A cached winter rerun made **zero requests** and took 12.22 s including both
maps. Each date retains about 1 MB including records, PNGs and metadata.
These are individual laptop measurements, not controlled comparisons, VM
benchmarks or operational guarantees. ERA5 has not been benchmarked.

Pilot checks and limitations:

- Require the index to report eight three-hourly average samples with none
  missing (00, 03, ..., 21 UTC).
- Validate HTTP 206 ranges, bounded response sizes, GRIB2 message lengths and
  trailers, field/level/unit metadata, matching grids and cached file hashes.
- Restore Gaussian latitude row centers rather than using GDAL's affine
  approximation as uniform latitude spacing. Handle the Pacific longitude seam.
- Plot absolute heights in decameters with 6-dam contours. No anomaly baseline
  has been built.
- Wind shading is `sqrt(mean_u^2 + mean_v^2)`: **speed of daily-mean wind
  components**, not mean instantaneous speed, a daily maximum or gusts.
  Arrows show approximate direction, not parcel trajectories.
- Cache reuse verifies local hashes. Explicit `refresh = TRUE` re-fetches a
  date; automatic upstream revision detection is not implemented yet.

### Run from the project root in RStudio

```r
source("scripts/load-weather-circulation-pilot.R")
weather_pilot <- run_weather_circulation_pilot(
  as.Date(c("2023-03-01", "2024-07-15"))
)
weather_pilot$summary
browseURL(normalizePath(
  "data/diagnostics/weather-circulation-pilot/2023-03-01/height500.png"
))
```

The jet image is `jet250.png` in the same date directory. Choose at most four
dates per call. Use `refresh = TRUE` for fresh downloads and
`render_maps = FALSE` to skip plotting. Sourcing the loader makes no requests.
`scripts/run-weather-circulation-pilot.R` runs the default winter example.
Outputs stay under ignored `data/diagnostics/`, with `pilot-runs.csv` timing
history and per-date source indexes, metadata and hashes.

### Next decision gate

1. Review the map domain, projection, contour labeling and usefulness alongside
   PRISM and archived discussions.
2. Test a short recent-date sequence for freshness, then repeat the bounded
   benchmark on the VM. Test missing dates and partial responses.
3. Configure CDS access if an ERA5 comparison is wanted, then request matching
   dates/levels/domain only. No ERA5 request was submitted in this pilot.
4. Choose daily means versus fixed-time analyses, PRISM date alignment, and
   whether moisture or regional wind belongs in the first release.
5. Define a same-source 1991-2020 baseline, revision checks and failure handling
   before any baseline backfill or daily-publisher integration.

### Map presentation revision: October 26, 2026

**Approved by the user for the pilot:** broad Pacific domain; shared 480-612 dam
height ramp; 6-dam contours with stronger 30-dam index contours and modest
588/594-dam emphasis; categorical jet-speed shading and streamlines. Use these
settings consistently across dates and seasons. This approves the visual
design, not production deployment or a historical baseline download.

### Recent-date readiness test: October 26, 2026

Run from the project root in the laptop RStudio console:

```r
source("scripts/run-weather-circulation-recent-test.R")
swc_weather_recent$summary
browseURL(normalizePath(swc_weather_recent$preview))
```

The script probes the previous seven daily indexes (excluding the current
calendar day), selects the latest three with complete required fields, renders
six maps, and repeats processing with rendering disabled to check download-cache
reuse. It distinguishes HTTP 404/not-posted, request failures and invalid or
incomplete indexes. Reports and a local preview gallery are saved beneath
`data/diagnostics/weather-circulation-recent-test/`. No public-site or daily-job
changes occur. Failures while downloading/decoding/rendering stop the test;
operational retry/failure isolation remains future work.

Measured locally October 26:

- All seven indexes, **October 19-25**, contained the required complete fields;
  zero probe errors. Latest available **within this checked window**: October
  25 (one calendar day old). This is one observation, not a release-time guarantee.
- Built **October 23-25**, three consecutive dates and six maps, in **28.42 s**.
  The first pass transferred **750,124 bytes** across 12 requests.
- Availability checks separately transferred **220,175 bytes** across seven
  index requests. Total test: **31.08 s**.
- Second pass: **zero requests**, **0.37 s**, all three verified downloads reused.
  This does not demonstrate map-output reuse: plotting was disabled for that
  pass, and the pilot otherwise always redraws maps.
- The circulation test suite passed **45 checks**. VM timing, multiple-day
  monitoring, revision detection and production integration remain pending.

Repeat the same script to test another day. Existing date caches are reused;
availability indexes are deliberately checked again. For a bounded custom run:

```r
source("scripts/load-weather-circulation-pilot.R")
source("R/weather-circulation-recent-test.R")
swc_weather_recent <- run_weather_circulation_recent_test(
  lookback_days = 7L, sample_days = 3L
)
```

The user selected the **broad Pacific context** as the default: 120E-60W,
10N-70N. The local renderer now includes thin geographic/state boundaries and
stronger purple Arizona/New Mexico outlines with a thin white backing to
distinguish them from dark meteorological contours, with no city labels.

- **500 mb:** a fixed 480-612 dam blue/cream/gold/orange absolute-height ramp,
  with stronger color separation at 582, 588, 594, 600, 606 and 612 dam for
  summer ridges; identical color anchors and limits for every season.
  The map retains 6-dam contours, thicker 30-dam index contours, modest emphasis
  on the 588/594-dam ridge reference contours, and sparse numeric
  contour labels. A later same-source height-departure layer can replace the
  absolute shading while retaining actual height contours.
- **250 mb:** fixed wind-speed categories in knots (<40, 40-60, 60-80, 80-100,
  100-120, 120-140, 140-160, 160-180, 180-200, 200+), a single-row legend, and
  thin streamlines with directional arrows. These follow the daily-mean vector
  field; they are not storm tracks or air-parcel trajectories.
- Streamline interpolation uses the actual Gaussian latitude centers and
  corrects east/west flow for latitude. Integration stops at domain boundaries,
  missing/calm flow or returning loops; spacing limits clutter. Data-cell
  shading uses midpoint latitude edges rather than a uniform pixel height.
- Both sample dates are regenerated from cached inputs. Rendering always reruns
  in this pilot; the existing timing table above describes the initial layout,
  not a benchmark of this revised renderer.

No new fields or dependencies are required. Daily-mean versus fixed-time
comparison, anomalies, browser integration and production publication remain
separate next steps. Source data are unchanged by these presentation revisions.

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

**Current boundary:** small local comparisons and user map review. Do not start
a full historical download or daily-job integration.

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

These sources describe availability and access. The October 26 laptop pilot
measurements above are separate from source documentation; VM throughput and
operational daily runtime remain unmeasured.

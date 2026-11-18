# Daily weather and circulation maps: exploration scope

Status: **resumed for local scoping and bounded testing, October 26, 2026**.
An isolated CORe pilot now downloads three selected fields and renders two
circulation panels. Source selection and operational integration remain pending.
The public site and daily publisher are unchanged.

Next gate: [isolated VM benchmark and transfer commands](weather-circulation-vm-test.md).
The laptop and VM benchmarks passed. A date-linked local Daily Explorer
preview and opt-in daily adapter are implemented; production remains disabled.
See the [retained archive and daily workflow](weather-circulation-daily-workflow.md)
for staging gates, bounded revision rechecks and resumable backfill. All built
weather dates are retained; no moving 30-day deletion window is used.

## Date-linked Daily Explorer preview

The VM benchmark reported PASS: six maps in 12.604 s, test duration 13.716 s,
whole script 18.17 s, and zero requests on the second download-cache pass.
The latest complete date checked was October 25, one day behind the October 26
test. These are single-run measurements, not an operational release guarantee.

Run from the project root in the laptop RStudio console:

```r
source("scripts/build-daily-explorer-circulation-preview.R")
source("scripts/serve-daily-explorer-circulation.R")
```

The separate preview opens at `http://127.0.0.1:8767/`. It copies the last seven
dates from the existing local Daily Explorer, without rebuilding or downloading
PRISM, and prepares circulation for the last three of those dates. On the
current laptop snapshot these are October 3-5; older dates intentionally
exercise the unavailable state. If no local explorer exists, first run
`scripts/build-daily-explorer.R` against the available processed PRISM cache.
The preview directory is `data/diagnostics/daily-explorer-circulation/`.

- A collapsed **Weather maps** section follows the exact selected date.
  **500-mb heights** and **250-mb jet** tabs show one map at a time. The selected
  tab persists across dates; inactive maps are not fetched until selected.
  Arrow keys and Home/End switch tabs, with standard tab/tabpanel labeling.
  Its manifest is requested only when opened, and images use lazy loading.
  Changing to an unavailable date clears previous images rather than substituting
  a different date. Request races cannot replace the current selection with an
  earlier selection's images. Image/manifest failures offer retry and leave
  PRISM browsing intact.
- Existing public payloads do not opt in. The panel requires both an explicit
  local preview flag and non-publication mode, so the normal daily publisher
  neither generates nor requests circulation assets. PRISM validation remains
  intact, with separate circulation metadata and image paths.
- A new render cache hashes selected source inputs, renderer functions and
  relevant package versions, then verifies PNG hashes. Changed sources, changed
  renderer code or corrupted maps trigger a rebuild. The three-date repeat test
  reported REUSED for all dates, zero requests and 0.14 s of combined map-builder
  time. Source rechecks are still explicit; upstream revision detection is not
  automatic yet.
- Local tests cover source/render cache invalidation, isolated build failures,
  exact dates, lazy loading, unsafe manifests, failed assets and request races.
  Browser review confirmed October 4/5 maps and the October 2 unavailable state.

Next: user review of the local panel, followed by bounded upstream-revision and
freshness policies, optional production-adapter failure handling, and VM staging
review. Do not enable daily production or download a historical baseline yet.

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

### Moisture/IVT inventory findings: October 26, 2026

The user selected moisture amount **and transport** as the next local scope:
prefer PWAT shading with IVT arrows, rather than interpreting a single-level
wind as transport through the whole column. This is not yet a public map or
part of the optional daily weather adapter.

`scripts/inventory-weather-moisture.R` checks daily and 12 UTC three-hourly
`pgb`/`flx` inventories for March 1, 2023 and July 15, 2024. Eight small index
requests transferred 135,457 bytes in 2.27 seconds locally. No GRIB fields were
downloaded. Results are saved in `data/diagnostics/weather-moisture-inventory/`.

- **PWAT:** directly indexed in `flx` as `PWAT:atmos col`, with daily
  eight-sample analysis means and individual three-hourly analyses. CPC's
  documented units are kg/m², convertible to mm and inches of water.
- **Direct IVT:** no integrated eastward/northward vapor-transport fields were
  identified among the full variable lists in these eight sample inventories.
  This is a sample finding, not proof about every possible CORe product/date.
- **Do not confuse `UFLX`/`VFLX` with IVT:** CPC defines them as surface momentum
  fluxes in N/m². They are not column water-vapor transport components.
- **Calculation inputs:** specific humidity, U/V wind and surface pressure are
  available at analysis times. A pressure-level IVT estimate would need an
  explicitly documented vertical range, integration/terrain treatment,
  completeness checks and validation. Do not use below-ground pressure levels.
- **Daily averaging:** calculate humidity-times-wind fluxes at each subdaily
  sample before averaging. Products of daily-mean humidity and wind do not
  reproduce daily-mean transport. CORe cloud fields are ensemble means: their
  humidity-times-wind product also omits ensemble covariance, so a derived IVT
  estimate must not be labeled an exact ensemble-mean moisture flux.

For a tentative 1000-300 hPa calculation at ten pressure levels plus surface
pressure, the checked 12 UTC inventories select 31 fields and about 2.94 MB
(winter) or 3.26 MB (summer). Multiplying those single-time sizes by eight gives
an **unmeasured projection** of about 23.5-26.1 MB and 248 individual field
requests per daily calculation, plus indexes/PWAT. Other times can differ in
size. Request grouping and a reduced domain may improve this; do not present
this estimate as a measured daily download benchmark or finalized method.

Next gate: benchmark a bounded calculated-IVT pilot using all eight times for
one winter and one monsoon day, or explicitly choose a fixed-time alternative.
The latter would be a dated analysis snapshot, not a daily-mean product. Compare
the derived column water with direct PWAT to assess vertical truncation and
terrain effects; do not silently redefine full-column PWAT as a limited layer.
Measure transfer **and request count** before deciding daily cadence. A
separate source's precomputed IVT would need its own timing/consistency review.

#### One-day IVT prototype result: retain as an experiment, defer daily use

The user authorized a prototype with instructions to move on if overhead was
too high. `scripts/run-weather-ivt-pilot.R` now implements one date only, with
120-second, 40-MB and 270-request guards and an early-stop projection check.
It is **not loaded by the daily publisher** and adds no public tab or archive
backfill. The default example is March 1, 2023; do not run a seasonal download.

The daily estimate integrates q*u and q*v at ten pressure levels from 300 to
1000 hPa, clips the lower boundary to surface pressure, then averages the
components across all eight analysis times. Below-ground level values are not
used. Where surface pressure falls between levels, the lowest above-ground
humidity/flux is extended to the boundary; levels below 1000 hPa and above
300 hPa are omitted. These approximations, plus products of ensemble-mean
inputs, prevent calling it exact full-column ensemble-mean IVT. Direct full-
column PWAT supplies the shading; estimated transport supplies the arrows.

Findings:

- The first attempt stopped at the PWAT grid check: `pgb` and `flx` encode
  identical N128 Gaussian definitions except a 0.000125-degree rounding
  difference in the first/last latitude. The prototype accepts only that
  narrowly verified endpoint discrepancy and uses exact Gaussian row centers.
  It does not resample using GDAL's affine latitude approximation.
- Initial attempt: **34 requests, 3,102,610 bytes, 12.51 s**. Resumed completed
  run reused those fields: **226 further requests, 20,824,719 bytes, 56.64 s**.
  Combined observed effort: **260 requests, 23,927,329 bytes and 69.15 s**.
  This is cumulative across a repair/resume, not an uninterrupted cold-run
  benchmark. `first-complete-summary.csv` preserves the completed-run metrics;
  subsequent cached reruns overwrite `summary.csv` only.
- The pressure-layer water estimate had a global median ratio of **0.957** to
  direct daily PWAT where PWAT exceeded 5 mm. This is a consistency diagnostic,
  not independent IVT validation. Transport magnitude had a global 99th
  percentile near **602 kg m^-1 s^-1**, maximum near **1315**.
- Outputs: `data/diagnostics/weather-ivt-pilot/2023-03-01/pwat-ivt-daily.png`
  and `pwat-ivt-12utc.png`. The arrows include a 500 kg m^-1 s^-1 reference key.
  Terrain-clipping and analytic constant-profile tests passed.

**Recommendation:** defer operational calculated IVT. One date is feasible,
but a three-date revision window could approach three minutes and roughly
72 MB/780 requests before other weather maps; a historical backfill multiplies
that cost. Those are extrapolations, not measured multi-date runs. This also
introduces substantially more scientific/terrain assumptions than direct
fields. Keep the prototype for event studies. Direct PWAT remains a lightweight
candidate; any single-level wind overlay must be labeled as flow at that
level, not column-integrated transport. No such alternative was enabled here.

#### Lightweight alternative: PWAT, sea-level pressure and low-level winds

At the user's request, a separate two-date prototype now matches the general
PWAT/MSLP/850-mb-flow layout of the supplied example. It remains outside daily
publishing and the public weather archive.

```r
source("scripts/run-weather-moisture-pilot.R")
swc_moisture_pilot$summary
```

Outputs are `data/diagnostics/weather-moisture-pilot/DATE/pwat-mslp-wind850.png`
for March 1, 2023 and July 15, 2024. Both use the same 0-3+ inch PWAT ramp,
labeled 4-hPa sea-level-pressure contours, sparse wind arrows with a 20-knot
reference key, broad Pacific domain and purple AZ/NM outlines. PWAT shading
is full-column water, not rainfall or an anomaly. Arrows are daily-mean winds
at 850 mb, not IVT, gusts or trajectories. Sea-level pressure is the CORe
`MSLET` reduced-pressure field and requires caution over high terrain.

Fields: daily PWAT (`flx`), daily MSLET and U/V winds (`pgb`), plus surface
pressure at each of the eight analysis times. **A wind cell is withheld if
surface pressure is missing or at/below 850 hPa at any time**, rather than
screening against daily-mean pressure alone. PWAT and pressure contours remain
visible where winds are masked. All selected daily fields must report eight
samples with none missing; units, wind level, valid time and Gaussian geometry
are checked. The known small `flx`/`pgb` endpoint-rounding discrepancy is handled
using the exact Gaussian row centers without changing source files.

Initial laptop measurements (individual runs, not VM benchmarks):

| Date | Requests | Transfer | Download | Total including decoding/rendering |
| --- | --- | --- | --- | --- |
| 2023-03-01 | 22 | 1,710,104 bytes | 5.42 s | 16.09 s |
| 2024-07-15 | 22 | 1,761,211 bytes | 4.78 s | 7.31 s |

The summer case ran in a warm R process after the winter case. These timings
include the stricter eight-time terrain mask and are substantially lighter
than the IVT experiment. Historical pilot caches reuse locally verified source
files but do not implement operational revision detection. Repeated calls
still redraw maps. Terrain-mask unit tests cover below-ground, missing and
exact-ground-level cases.

For a later comparison, the same function supports `wind_level = 700L`, reusing
PWAT, pressure and surface-pressure caches and downloading only the two new
wind records per date. 850-mb winds are intentionally absent over much of the
elevated Southwest; 700 mb would provide more inland context but represents a
different layer. Review these examples before choosing a default or adding a
third operational Weather maps tab.

Automatic pressure-center labels are now included in this prototype: blue H,
red L and original-grid central pressure rounded to whole hPa. Detection uses
one native-cell weighted smoothing, a 400-km local-extremum check, at least
2-hPa median contrast in a 500-800-km annulus with 90% directional support,
900-km minimum label spacing and a cap of ten centers (at most five per type).
The annulus uses context beyond the displayed northern/southern boundary to
avoid inventing centers at clipped edges. Centers near map edges and those
with MSLP minus mean surface pressure above 100 hPa are suppressed; the latter
is a conservative elevation proxy using existing inputs, not a guarantee that
all terrain-related artifacts are eliminated. These are prototype display
choices, not universal meteorological standards or a storm-tracking algorithm.
Contour-label placement avoids the H/L symbols. The two cases produced nine
and seven centers, with detection taking about 0.4-0.5 seconds per map and no
new requests. Fourteen unit checks cover wind masking and center detection,
including weak, flat, sloping, edge and elevated-terrain cases.

Primary inventory reference:
[CPC CORe file types, field names and units](https://ftp.cpc.ncep.noaa.gov/CORe/get_core/get_core.txt).

To repeat the inventory from RStudio:

```r
source("scripts/inventory-weather-moisture.R")
swc_moisture_inventory$summary
```

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

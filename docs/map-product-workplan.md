# PRISM map product workplan

This workplan scopes the PRISM-derived maps for Southwest Climate Watch. It
separates the operational core from useful seasonal products and from advanced
products that require additional methods or non-PRISM information.

## Product principles

- Keep the public collection compact enough that users can find a map quickly.
- Use percentile ranks as the primary precipitation comparison because they
  remain interpretable across climates ranging from the lower Colorado deserts
  to high-elevation northern Arizona and New Mexico.
- Pair percentiles with observed totals and selected percent-of-normal maps.
  These answer different questions and should not be treated as substitutes.
- Retain Fahrenheit for temperature and inches for precipitation.
- Use the fixed 1991-2020 normal for operational climate comparisons unless a
  product is explicitly labeled as a full-record or long-record ranking.
- Derive daily mean temperature locally as `(maxt + mint) / 2`; do not request
  it separately from RCC-ACIS.
- Build reusable derived baseline caches before adding long accumulation maps.
  A daily update should not repeatedly reread decades of source grids.
- Maintain one validated map-product catalog for website navigation, enabled
  status, and display-mode selection. The catalog-driven expandable browser is
  implemented for all 51 current products, and the daily updater now honors
  each product's enabled status while preserving shared calculations.
  Categorical rendering is also connected to each product's catalog setting;
  continuous remains the default.

## Completed operational products

### Temperature

- Daily maximum, minimum, and mean temperature.
- Daily maximum-, minimum-, and mean-temperature departures from the
  1991-2020 normal.
- Daily maximum-, minimum-, and mean-temperature percentile ranks using a
  centered five-day seasonal window and R quantile type 8.
- Thirty-day maximum-, minimum-, and mean-temperature departures, calculated
  from the latest 30 daily grids and their matching 1991-2020 daily normals.
- Seven-, 30-, and 90-day mean-temperature percentile ranks. Each ranks the
  complete rolling mean against seasonally matched 1991-2020 rolling means;
  it is not an average of daily percentile ranks. Historical samples are
  cached by duration and ending calendar day.
- Thirty-day extreme warm-day frequency, counting days when maximum
  temperature exceeds the local centered-five-day 1991-2020 90th percentile.
- Thirty-day extreme cold-night frequency, counting nights when minimum
  temperature falls below the local centered-five-day 1991-2020 10th percentile.
- Thirty-day freeze-day count using minimum temperature at or below 32 degrees
  F, paired with its anomaly from the matching centered-five-day 1991-2020
  average count.
- First-freeze date in each August 1-July 31 season and departure in days from
  the median 1991-2020 first-freeze date. The normal requires freezes in at
  least 24 of 30 baseline seasons, and a new season replaces the previous map
  only after September 1 and 5 percent observed coverage.
- Last-freeze date in the same cold season and departure from the median
  1991-2020 date. Provisional current-season maps begin March 1 and become final
  after July 31; the same 24-of-30 reliability mask is applied.
- Calendar-year freeze-free season length and departure from the median
  1991-2020 length. Both the last January-July freeze and first August-December
  freeze are required; current-year maps use September and coverage guards.

### Precipitation

- Observed 1-day, 7-day, 30-day, and 90-day totals.
- Exact 7-day, 30-day, and 90-day percentile ranks against the centered five-day
  1991-2020 seasonal distribution.
- Thirty-day and 90-day precipitation percent of normal, with unstable ratios
  to historical means below 0.10 inch suppressed.
- Water-year-to-date total, percent of normal, and empirical percentile rank
  against matching water-year 1991-2020 accumulations.
- Current dry-spell length and seasonal percentile rank using a 0.04-inch
  wet-day threshold.
- Longest dry spell in the trailing 180 days and its seasonally matched
  percentile rank using the same threshold. The moving window replaces the
  earlier water-year proposal so normal spring dryness does not dominate the
  product for the remainder of the year.
- Ninety-day wet-day count and seasonal percentile rank using the same
  0.04-inch threshold.
- Ninety-day wet-day intensity and seasonal percentile rank. Intensity is the
  mean precipitation on qualifying wet days; trace amounts are excluded and
  zero-wet-day cells are omitted.
- Ninety-day very-wet-day contribution and seasonal percentile rank. The share
  uses days above the local annual wet-day p95 threshold, includes all
  precipitation in the denominator, and masks totals below 0.10 inch.
- Maximum rolling three-day precipitation so far in the active water year and
  its provisional percentile against complete water years 1991-2020.
- Water-year precipitation concentration: the percentage of the current total
  supplied by the wettest three-day period, with totals below 0.10 inch masked.
- Fourteen-day change in the 30-day precipitation percentile rank, with
  positive values indicating wetting and negative values indicating drying.

## Phase 1: high-value hydroclimate context

Build the shared accumulation-climatology engine first, then expose the maps.

1. **90-day precipitation total and percentile rank — implemented**
   - Extends the existing 7- and 30-day sequence to a seasonal timescale.
   - Use the same ending-date and centered five-day comparison convention.
2. **30-day and 90-day precipitation percent of normal — implemented**
   - Current accumulation divided by the mean historical accumulation for the
     same seasonal window, multiplied by 100.
   - Always display alongside totals or percentiles because percentages can be
     unstable where normal precipitation is near zero.
3. **Water-year-to-date precipitation total — implemented**
   - Accumulate from October 1 through the latest common PRISM date.
4. **Water-year-to-date percent of normal and percentile rank — implemented**
   - Compare with historical October 1 through matching-calendar-date totals.
   - The map title must state both the water year and ending date.
5. **Current dry-spell length and seasonal percentile — implemented**
   - Count backward from the latest date while precipitation remains below
     0.04 inch. This includes and improves upon days since measurable rain.
   - Cap the display scale while retaining the uncapped value in the raster.
6. **90-day wet-day count and seasonal percentile — implemented**
   - Count days with at least 0.04 inch during the trailing 90-day period.
   - Compare the count with matching 90-day periods from 1991-2020 using the
     centered five-day ending-date convention.
7. **Water-year maximum 3-day precipitation and magnitude percentile — implemented**
   - Retain the largest complete rolling three-day total since October 1.
   - Rank the maximum-so-far against maxima from complete water years
     1991-2020 and label the active-year rank provisional until September 30.

### Phase 1 processing prerequisite

Precompute or incrementally maintain historical rolling and water-year
accumulation samples. The operational updater should read a compact baseline
sample for the target calendar date instead of reconstructing 30 to 365 days
for every baseline year on every run. Cache records must include duration,
ending calendar day, baseline, wet-day convention where relevant, source
signature, build time, and checksum.

Implementation began with calendar-day rolling-accumulation sample caches.
Each cache is keyed by accumulation duration, baseline, centered-window method,
and ending calendar day. It is reused when the selected source checksums are
unchanged and rebuilt when provenance changes.

Historical water-year-to-date samples are also implemented. Baseline labels
1991-2020 mean 30 water years, so WY1991 begins October 1, 1990 and WY2020 ends
September 30, 2020. A cache contains one cumulative layer per water year through
the target calendar day. October 1 always builds a one-day reset sample. Later
dates can add the new historical daily layers to the prior calendar day's
validated cache; if the parent is absent or stale, the requested date is built
directly. February 29 samples interpolate corresponding February 28 and March 1
cumulative totals and build directly. The separate water-year cache manifest
records whether each file was direct or incremental and, when incremental, the
validated parent path and checksum.

## Precipitation behavior metrics from daily grids

Daily precipitation supports maps of persistence, frequency, intensity, event
concentration, and timing in addition to accumulated amount. The following
options are scoped for this project.

### Tier A: recommended monitoring products

1. **Current dry-spell length and seasonal percentile**
   - Count consecutive days below 0.04 inch ending on the latest date.
   - Publish days and its percentile relative to historical spells ending near
     the same calendar date. The percentile makes a 20-day dry spell in July
     distinguishable from the same duration in winter.
   - This subsumes the simpler `days since measurable precipitation` product.
2. **Wet-day frequency for the latest 90 days — implemented**
   - Count days with at least 0.04 inch and compare with the 1991-2020
     distribution for matching 90-day periods.
   - Publish paired count and percentile maps. The 90-day period is long enough
     to show sustained event frequency while remaining useful for monitoring.
3. **Water-year maximum 3-day precipitation and magnitude percentile — implemented**
   - Retain the largest rolling three-day total observed since October 1.
   - Rank it against complete historical water-year maxima. During an active
     water year label the value `maximum so far`; its historical rank is
     provisional until the water year ends.
4. **Precipitation concentration — implemented**
   - Calculate the percentage of water-year precipitation supplied by the
     wettest three-day event: `100 * max_3day / water_year_total`.
   - This distinguishes precipitation delivered in one major burst from the
     same total distributed among many events. Mask or flag cells whose
     water-year total is too small for a stable ratio.
5. **Recent precipitation-percentile change — implemented**
   - Difference between the current 30-day precipitation percentile and the
     percentile 14 days earlier.
   - Positive values identify rapid wetting; negative values identify rapid
     drying. Always pair it with the current 30-day percentile so change is not
     mistaken for current condition.

### Tier B: seasonal diagnostic products

1. **Longest dry spell in the trailing 180 days and percentile — implemented**
   - Complements current dry-spell length by retaining an earlier prolonged dry
     period even after rain occurs.
   - A seasonally matched moving window is more interpretable than a water-year
     maximum in the Southwest, where normal spring dryness would otherwise
     remain embedded in the product for many months.
2. **Maximum wet-spell length**
   - Longest run of days at or above 0.04 inch. This follows the established
     consecutive-wet-day concept but may be less informative than wet-day count
     in the Southwest, where convective rainfall is intermittent.
3. **Wet-day intensity — implemented**
   - Mean precipitation on qualifying wet days during the latest 90 days,
     analogous to the Simple Daily Intensity Index. Sub-threshold amounts are
     excluded and cells with no wet day are omitted.
   - Published with a percentile against seasonally matched 1991-2020 windows.
4. **Timing of the largest precipitation event**
   - Map the ending date of the largest three-day event, separately for the
     cool season (October-March) and monsoon season (June-September).
   - Do not calculate a simple water-year timing anomaly from one median date:
     winter and summer precipitation regimes can make the timing distribution
     bimodal. A categorical month/date map or season-specific timing percentile
     is more defensible.
5. **First substantial warm-season rain**
   - Map the first date after June 15 meeting a defined amount/duration rule,
     such as a one-day amount of at least 0.25 inch or a qualifying three-day
     total.
   - Label this `first substantial rain`, not `monsoon onset`. Meteorological
     monsoon onset is a regional circulation concept and should be calculated
     as a separate regional indicator if included.
6. **Contribution from very wet days — implemented**
   - Percentage of seasonal precipitation falling on days above the local
     wet-day 95th percentile. This identifies whether the season is being
     dominated by extreme events rather than frequent moderate rain.

### Tier C: exploratory rather than core monitoring

- **Precipitation center of mass:** date by which 50% of the final seasonal
  total occurred. It is meaningful only after the season is complete.
- **Gini or daily concentration index:** statistically useful but harder to
  explain than the wettest-three-day share.
- **Antecedent precipitation index:** exponentially weighted recent rainfall
  can approximate surface wetness, but the decay constant is assumption-heavy
  and it is not a substitute for observed soil moisture.
- **Grid-cell monsoon onset:** highly sensitive to the chosen precipitation
  threshold and can imply a meteorological definition that daily rainfall alone
  does not establish.

### Recommended compact behavior suite

Add four operational products after the accumulation cache is working:

1. Current dry-spell length with seasonal percentile.
2. Latest 90-day wet-day count with percentile.
3. Water-year maximum three-day precipitation with magnitude percentile.
4. Fourteen-day change in the 30-day precipitation percentile.
5. Longest dry spell in the trailing 180 days with seasonal percentile.
6. Wet-day intensity in the trailing 90 days with seasonal percentile.

Precipitation concentration and the trailing 180-day longest dry spell are now
implemented. Monsoon-specific onset and event-timing products are outside this
project because they are maintained in a separate project. Cool-season event
timing remains optional rather than part of the operational core.

## Phase 2: recent temperature and precipitation extremes

1. **30-day temperature anomalies — implemented**
   - Maximum, minimum, and mean temperature use the same ending date, averaging
     window, 1991-2020 normals, and fixed map scale.
   - The maximum and minimum products distinguish sustained afternoon and
     nighttime conditions; the mean product summarizes both.
2. **7-, 30-, and 90-day mean-temperature percentile ranks — implemented**
   - These provide compact week, month, and season views without tripling the
     collection into separate maximum- and minimum-temperature maps.
   - Rank each rolling mean against matching centered-five-day 1991-2020
     rolling means, using reusable double-precision calendar-day caches.
3. **Extreme warm-day frequency — implemented**, reported as the number of
   days in the latest 30 days above the calendar-day 90th percentile of
   maximum temperature.
4. **Extreme cold-night frequency — implemented**, counting nights in the
   latest 30 days below the calendar-day 10th percentile of minimum
   temperature.
5. **Maximum rolling 3-day precipitation this water year — implemented** and its percentile
   among historical water-year maxima.
6. **Freeze days and freeze-day anomaly**
   - The latest 30-day count using minimum temperature at or below 32 degrees F
     is implemented.
   - The matching centered-five-day 1991-2020 average-count anomaly is
     implemented. These are seasonal maps and should be emphasized during the
     relevant part of the year.
7. **First freeze date and departure from normal — implemented.** Seasons run
   August 1-July 31. The previous completed season remains displayed until the
   new season reaches the September 1 and 5-percent coverage thresholds.
8. **Last freeze date and departure from normal — implemented.** Provisional
   maps begin March 1, become final after July 31, and retain the previous
   completed season during August-February.
9. **Freeze-free season length and departure from normal — implemented.** The
   current calendar year replaces the completed-year map only after September
   1 and 5-percent observed coverage, and becomes final after December 31.

## Phase 3: climate-context products

The first historical archive pilot is implemented separately from the daily
map updater: eight seasonal maps each for WY1998 and WY2011, using a fixed
WY1982-WY2025 ranking set and 1991-2020 temperature normals. Its methods,
RONI labels, and local build command are in `docs/seasonal-archive.md`.
The pilot is not an ENSO composite and does not attribute each observed map
pattern solely to ENSO.

1. **Strong-El-Nino precipitation composite.** Define the event list and season
   from an authoritative ENSO index before calculating the PRISM composite.
2. **Strong-El-Nino temperature composite.** Use the same event definition and
   clearly label maximum, minimum, or mean temperature.
3. **Current water year minus the El-Nino composite.** Only publish during a
   qualifying event and retain the historical composite as the companion map.
4. **Analog-year comparisons.** Treat the analog-year list as an explicit,
   documented scientific choice rather than an automatically inferred set.

Although the composite fields are calculated from PRISM, ENSO classification
requires an external index and therefore is not a strictly PRISM-only product.

## Phase 4: advanced drought indices

- SPI-1, SPI-3, SPI-6, and SPI-12 may be valuable, but they require a separately
  validated distribution-fitting workflow, treatment of zero precipitation,
  and a sufficiently long fixed reference record. They should not be presented
  as ordinary z-scores.
- SPI should be implemented as its own documented module after the simpler
  accumulation, percentile, and water-year products are operational.

## Products not prioritized for the public map collection

- **14-day and 60-day totals:** largely redundant with the 7-, 30-, and 90-day
  sequence. They can remain available as configurable analysis outputs without
  occupying primary site navigation.
- **30-, 60-, 90-, and 180-day raw standardized precipitation anomalies:**
  precipitation is zero-inflated and strongly skewed, so `(P - mean) / SD` can
  be misleading. Use empirical percentiles now and validated SPI later.
- **Separate precipitation anomaly maps:** absolute anomalies are scientifically
  valid but add little public-facing information once total, percent of normal,
  and percentile are available. They can be generated for analysis or download.
- **Water-year standardized anomaly:** redundant with the more interpretable
  water-year percentile and subject to the same distributional problem.
- **Routine 1-day precipitation percentile:** most cells are dry on most days,
  making the map visually sparse and difficult to interpret. The annual wet-day
  p90, p95, and p99 thresholds remain useful for event classification.
- **Routine 3-day precipitation percentile:** reserve for a significant-event
  view; use maximum 3-day water-year precipitation for the standard extremes
  product.
- **A permanently named 2026-27 product:** implement a generic current-water-
  year and configurable analog framework so it remains useful in later years.

## Recommended implementation order

1. Derived accumulation cache and provenance tests.
2. Water-year total, percent of normal, and percentile maps.
3. 90-day total and percentile plus 30- and 90-day percent-of-normal maps.
4. Current dry-spell length and seasonal percentile.
5. Ninety-day wet-day count and percentile.
6. Water-year maximum 3-day precipitation and magnitude percentile.
7. Fourteen-day change in the 30-day precipitation percentile — implemented.
8. Thirty-day maximum, minimum, and mean temperature anomaly maps — implemented.
9. Seven-, 30-, and 90-day mean-temperature percentile maps — implemented.
10. Precipitation concentration and trailing 180-day longest dry spell — implemented.
11. Extreme-temperature frequencies and seasonal freeze products — implemented.
12. ENSO composites and configurable analog-year comparisons.
13. Separately validated SPI module.

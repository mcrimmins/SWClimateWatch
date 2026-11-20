# Early Historic Years local pilot

Selected years: WY1896, WY1934 and WY1977. This bounded pilot precedes any
WY1896–1981 archive expansion. Each page has 21 maps: precipitation total and
percentile, mean temperature, temperature departure and percentile for Water
year (October–September), Cool season (October–March), Spring (April–June),
Monsoon (July–September), plus September SPI-12 under Water year.

WY1896 is October 1895–September 1896, the first complete water year supported
by the January 1895 monthly cache. Ranks remain retrospective over the matching
completed-year comparison record, including later years and the target once.
Temperature departures retain 1991–2020; September SPI-12 retains the existing
fixed gamma/zero-adjusted calibration and support/fit guards. No early-period
reference shortening or daily data reconstruction is used.

Daily-detail plots are not included: the existing archive detail covers
WY1982–2025. Historical Snow maps start WY2005. A verified DJF RONI value has
not been attached to these pilot years; no neutral label, current advisory or
another year's map is substituted. All three disclosures are visible in the
appropriate grouped sections, collapsed by default.

Run from laptop R/RStudio:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/build-historic-monthly-early-pilot.R")
source("scripts/check-historic-monthly-early-pilot.R")
source("scripts/build-historic-monthly-early-pages.R")
source("scripts/preview-historic-monthly-early-pilot.R")
```

The build reads the existing monthly cache and can seed verified full-record
references and SPI fits from `data/diagnostics/historic-monthly-archive`.
It does not download anything, change operational pages, change the transferred
publication bundle, extend the live navigation or upload to S3. Map results
checkpoint by year/period; reruns reuse verified outputs. The output-folder
lock prevents overlapping builds of this pilot.

Outputs:

- Maps/numeric grids: `data/diagnostics/historic-monthly-early-pilot`.
- Page sources/rendered site: `data/diagnostics/historic-monthly-early-site`.
- Preview entry: `data/diagnostics/historic-monthly-early-site/_site/index.html`.

Expected numeric check: PASS, three years, 63 maps, zero requests. Expected
rendered check: PASS, three pages, 63 monthly maps, zero daily-detail and zero
Snow maps. Validation covers source/output hashes, full-record ranks, normal
departures, SPI/support masks, seasonal partition, exact year coverage, season
tabs, all image links/checksums, availability notices and absence of fabricated
ENSO labels or analytics. Review all three years before selecting the remaining
backfill; do not use the existing 44-year publication helper for this pilot.

November 19 local verification: all 63 maps built in 395 seconds with zero
requests, reusing the verified references and SPI fit. Independent numeric
checks passed for all 12 year/period combinations. All three rendered pages
passed with 63 monthly images, zero daily-detail/Snow images and the required
availability notes. Early-page tests passed (37 assertions), existing layout
tests passed (587), and the existing publication tests passed (97). User review
is the next step; no staging or production publication was performed.

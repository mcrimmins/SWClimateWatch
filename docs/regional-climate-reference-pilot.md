# Annual regional climate reference pilot

Local development, November 14, 2026. No operational site changes, download
requests, monthly-updater changes or publication steps are added.

Local verification: 1,080 inputs checked; both maps rendered and visually
reviewed; 14 unit checks and all 16 independent point comparisons passed.
The initial audit/build took about 3m 11s; an unchanged cached rerun took about
11 seconds on the laptop. These are local measurements, not daily VM costs.

Run from the project root in the laptop RStudio console:

```r
source("scripts/build-regional-climate-reference-pilot.R")
regional_reference_pilot$summary
regional_reference_pilot$samples
source("scripts/check-regional-climate-reference-pilot.R")
source("scripts/serve-regional-climate-reference-pilot.R")
```

Review <http://127.0.0.1:8786/> while RStudio remains open. The gallery links to
both full-resolution PNGs, city/grid-cell samples, methods and source inventory.
Outputs live in `data/diagnostics/regional-climate-reference-pilot/`.

## Methods

Use monthly PRISM precipitation, maximum-temperature and minimum-temperature
grids for January 1991 through December 2020: 360 months and 1,080 inputs.
Verify cache request signatures, input checksums, month stamps, geographic
alignment, units/ranges and temperature pairing using the existing read-only
monthly audit. Write the pilot's audit reports in its own diagnostic folder.
Do not alter the monthly manifest or input files and do not fetch missing data.

- Annual precipitation is the sum of the twelve calendar-month totals. The
  reference is the arithmetic mean of the 30 complete annual totals, in inches.
- Monthly mean temperature is estimated as (monthly mean daily maximum +
  monthly mean daily minimum)/2. Weight months by their actual number of days
  within each calendar year, including February 29. Then average the 30 annual
  means equally; do not give leap years greater weight in the climatology.
- A missing or invalid month withholds that year's value for that variable.
  Require all 30 complete years independently for precipitation and temperature;
  no zero filling, interpolation or reduced-sample climatology. Separate sample-
  year rasters retain coverage evidence. Valid zero precipitation stays zero.
- Maps describe the reference climate, not recent anomalies or full-record
  rankings. These are project-calculated PRISM references, not downloaded
  official NOAA station normals. Sample points represent their PRISM grid cells.

Use existing Southwest boundaries, city labels, map extent and branding.
Categorical scales include open-ended tails and a distinct unavailable class;
display categories never cap or change the saved numerical values.

## Verification and caching

```r
testthat::test_dir(
  "tests/testthat", filter = "^regional-climate-reference$", reporter = "summary"
)
source("scripts/build-regional-climate-reference-pilot.R")
```

The second build should report REUSED, with zero requests. Cache checks bind
source checksums, reference years, aggregation/display rules and output hashes;
source changes or damaged outputs require rebuilding. Missing inputs stop the
build rather than trigger downloads. The numerical references and coverage
rasters are GeoTIFFs; PNGs, source inventory, method/sample/summary CSVs and a
small HTML gallery are local review artifacts.

The independent check samples eight locations from the original monthly grids,
expands monthly temperatures to actual daily calendar dates, and compares the
result to the saved reference rasters. It does not call the annual aggregation
helpers; tolerance is 0.0001 for Float32 storage. All 16 comparisons must pass.
Results are saved in `independent-check.csv`.

After annual-map review, separately scope JFM/AMJ/JAS/OND seasonal views and the
Climate of the region page. No navigation, catalog/hotlink or daily publication
integration is enabled by this pilot.

## Seasonal extension: November 14 local review

The annual maps were accepted locally. Build four calendar-quarter companions
for each variable and preview them alongside the original annual maps:

```r
source("scripts/build-regional-seasonal-reference-pilot.R")
regional_seasonal_reference_pilot$summary
source("scripts/check-regional-seasonal-reference-pilot.R")
source("scripts/serve-regional-seasonal-reference-pilot.R")
```

Review <http://127.0.0.1:8787/>. Definitions follow the previously scoped calendar
quarters and are printed on every map and in the gallery:

| Name | Months |
| --- | --- |
| Winter | January-March |
| Spring | April-June |
| Summer | July-September |
| Fall | October-December |

Each seasonal precipitation reference averages 30 complete three-month totals.
Each seasonal temperature reference first weights its three monthly means by
actual days within that year (including leap days in winter), then weights the
30 season-years equally. Require all 30 seasons independently for each period
and variable. A missing winter input does not invalidate an otherwise complete
summer reference; annual coverage remains separate. No imputation is used.

All four seasonal precipitation maps share one scale with finer low-total
classes; all four seasonal temperature maps share one broader temperature
scale. Annual maps retain their own scales. Display tails are open-ended and do
not cap saved numerical values. These map totals/means, not seasonal anomalies.

The seasonal builder reuses the annual pilot's read-only source audit and
verifies input hashes before using the same 1,080 cached grids. Separate
per-quarter completion records bind dependencies, methods, plotting rules and
output checksums. Unchanged seasons are reused; a damaged output or changed
quarter input rebuilds that quarter. Annual preparation follows its own existing
cache rules. Interrupted work resumes from completed quarters on rerun.

Outputs are isolated in `data/diagnostics/regional-seasonal-reference-pilot/`.
The combined gallery copies the two annual PNGs into its own folder rather
than editing the annual pilot or its completion record. The independent checker
samples the original monthly inputs once, expands temperatures to calendar days
and verifies 64 seasonal plus 16 annual point comparisons. No climate downloads,
live-site pages, catalog entries or daily-runner changes are added.

Local verification passed: all eight seasonal maps rendered, 35 combined unit
checks passed, and all 80 independent annual/seasonal point comparisons passed.
An unchanged rerun reused the annual maps and all four seasonal pairs in about
nine seconds on the laptop, with zero requests. Representative seasonal PNGs
were visually inspected; user gallery review remains pending.

Unit checks for both increments:

```r
testthat::test_dir(
  "tests/testthat", filter = "regional-(climate|seasonal)-reference",
  reporter = "summary"
)
```

# SNODAS October-May daily reference baseline

This is a **local, resumable reference-grid build**, not a download or a
published snow-map update. It uses the screened, processed regional SWE/depth
grids for WY2005-WY2025. The baseline covers all 244 October-May month-days:
243 are calculated from historical daily observations, and February 29 is
interpolated from its two neighboring reference dates. The short 21-year
record must be labeled **SNODAS 2005-2025 reference**, not a long-term
climate normal or a near-record ranking.

## Calculation and interpretation

- On ordinary dates, each historical water year contributes one effective
  sample. Its SWE is the median of the target day and two neighboring days;
  its snow contribution is the fraction of those days with SWE at least
  **0.1 inch**. At least **three valid days** are required at each cell for a
  year to contribute. The final median SWE is the median of the yearly SWE
  samples; snow frequency is the mean of the yearly snow fractions. It is a
  fraction from 0 to 1, interpretable as the share of valid days in the
  five-day seasonal window with at least 0.1 inch SWE, with years weighted
  equally. It is **not** the percentage of years snowy on the exact date.
- October 1 and May 31 use the three available in-season days. October 2
  and May 30 use four. All other non-leap reference dates use five. No
  September or June data are pulled into the October-May baseline.
- NSIDC-documented whole-day missing files or missing SWE are counted as
  missing, never as snow-free. An unverified processed pair **not** in the
  errata stops that date's build. Each available SWE/depth pair passes the
  in-memory consistency screen before grid alignment.
- A cell's median and frequency are hidden unless at least **15 water years**
  contribute. `sample_years.tif` records the number of contributing years.
- February 29 is the cellwise average of the February 28 and March 1
  **reference** median-SWE and snow-frequency grids. Its `sample_years.tif`
  is the smaller of the two adjacent support-year counts, **not** a direct
  count of leap-day observations. The QC file marks this layer as
  `interpolated`.

The design was selected after the
[three-date calendar-day and five-day pilots](snodas-climatology-pilot.md).
February 15's five-day pilot correctly handles
the documented missing February 14, 2007 and screens the 85 previously
flagged cells on February 17, 2015.

## Output, resumption, and storage

The default output root is
`data/processed/snodas/az-nm-pad050/climatology/wy2005-wy2025/daily/centered-05day/`.
Each `MM-DD/` directory contains `median_swe.tif`, `snow_frequency.tif`,
`sample_years.tif`, `qc-summary.csv`, and a completion marker with the method
parameters and output checksums. A rerun skips only dates whose marker and
files validate; partial dates are rebuilt in their dedicated output folder.
Changing the years or method parameters invalidates the marker and triggers
a rebuild. If historical processed sources are deliberately revised without
changing these parameters, rebuild the affected dates explicitly; source
content is not automatically hashed during the resume scan. Do not run two
baseline jobs simultaneously against the same output root.

The February five-day pilot's three GeoTIFFs total about 1.2 MB. A simple
244-day extrapolation is roughly **0.3 GB**, but the actual size varies by
season and terrain; this is an estimate, not a storage limit. The long job
re-reads many local daily grids and may take hours. It makes **no network
requests** and does not retain another copy of the source rasters.

## Run from the RStudio console

With the project root as `getwd()`:

```r
source("scripts/load-snodas-daily-climatology.R")

# Preview only; no grids are written.
preview <- run_snodas_daily_climatology(max_days = 1L, dry_run = TRUE)
preview$scheduled

# Small first check of the October 1 edge rule.
first_day <- run_snodas_daily_climatology(
  month_days = "10-01", max_days = 1L
)
first_day$after
```

The first local October 1 check completed and validated its checksum marker.
It used 62 processed pairs and one NSIDC-documented missing date (October 1,
2006), with no additional cell exclusions. Consequently the maximum
support count is 20 years on this date. Median SWE is zero across the
eligible footprint, as expected for the start of the cool season, while
snow frequency is positive in some cells. A resumed preview schedules
October 2 next, confirming the completed day is skipped.

After inspecting that output, run the whole baseline locally. The command
can be repeated after an interruption; finished dates are skipped:

```r
full_baseline <- run_snodas_daily_climatology(max_days = Inf)
table(full_baseline$after$complete)
```

To limit a session, use a finite cap such as `max_days = 10L`, then rerun.
February 29 is scheduled last so February 28 and March 1 are already
validated. The runner reports progress for every date and every five
historical years within that date. Test the code without the full raster job
using `testthat::test_dir("tests/testthat", filter = "snodas-daily-climatology")`.

No snow anomaly or change maps are published by this builder. Those should
be designed and validated against the completed reference before being
added to the site or daily update cycle.

## Completed local build check

The WY2005-WY2025 run completed all **244 of 244** reference dates. Completion
markers and checksums validate for every date. Spot checks of October 1,
December 15, February 15 and 28, March 1, April 15, and May 31 found one
layer per product, the expected reference date, nonnegative median SWE,
snow frequency within 0-1, and support counts no larger than 21. February
29 matches the average of its neighbors to floating-point precision. The
three GeoTIFFs for all dates total about **0.151 GiB** locally.

Across the overlapping five-day QC windows, the five NSIDC-documented
missing source dates recur 23 times. The only distinct SWE/depth cell flags
remain the previously audited dates: December 19, 2012 (382 cells),
February 17, 2015 (85), and April 30, 2015 (12). Their window appearances
sum to 2,395 exclusions; that is **not** 2,395 distinct new bad cells.
These are plausibility and integrity checks, not independent validation of
SNODAS SWE against field observations.

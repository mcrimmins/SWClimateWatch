# SNODAS calendar-day climatology pilot

This is a **local development pilot**, not yet a published snow map or a
completed operational climatology. It uses the screened October–May
WY2005–2025 SWE/depth record described in the
[SNODAS availability and quality audit](snodas-availability-audit.md).
The pilot checks three representative dates—December 15, February 15, and
April 15—before choosing a smoothing window or making seasonal anomaly maps.

## Calculation

For each selected calendar date, take **one SWE snapshot per water year**.
October–December dates belong to the following water year (for example,
December 15, 2018 is WY2019). The source is SNODAS's daily 06:00 UTC
snowpack state; daily SWE is not accumulated across the season. Each SWE/depth
pair passes `screen_snodas_analysis_pair()` before the SWE layer is moved by
nearest-neighbor sampling to the fixed post-2013 1-km comparison grid.
Original daily GeoTIFFs are not rewritten.

The pilot produces three rasters for each date:

- `median_swe.tif`: median SWE across the valid historical years, in inches;
- `snow_frequency.tif`: fraction of valid years with SWE at least **0.1 inch**;
- `sample_years.tif`: number of valid, screened historical years at each cell.

Median and frequency are hidden where fewer than **15 years** are valid.
Historical no-data and quality-screened cells never count as snow-free.
The 0.1-inch snow threshold and 15-year minimum are **pilot choices** to
review against maps, not final scientific standards. Each year contributes
at most one value per date; nearby days are not pooled as independent samples.
February 29 is excluded until a leap-day policy is chosen. A short centered
seasonal window may be evaluated later if the calendar-day median is too
jagged, but it should preserve one effective sample per water year.

## Run one date locally in RStudio

From the project root in the R console, preview the processed pairs without
starting a calculation or network request:

```r
source("scripts/load-snodas-climatology-pilot.R")
pilot_plan <- plan_snodas_baseline_day("02-15")
table(pilot_plan$ready)
```

All **21 of 21** February 15 pairs, as well as the December 15 and April 15
pairs, were ready at the full-baseline completion check. Build the first date
locally and inspect its paths and the quality-screen summary:

```r
pilot_february <- build_snodas_baseline_day("02-15")
pilot_february$paths
subset(pilot_february$qc, excluded_cells > 0)
```

The default output is under
`data/processed/snodas/az-nm-pad050/climatology/wy2005-wy2025/` in a
`pilot-calendar-day/02-15/` subdirectory. The output folder holds the three
GeoTIFFs and `qc-summary.csv`, which records per-year exclusions and the
pilot parameters. The function reports progress every five historical years.
It refuses to overwrite existing pilot outputs unless `overwrite=TRUE` is
explicitly given; that option affects only the selected date's pilot outputs.

After inspecting February, December and April can be built separately:

```r
pilot_december <- build_snodas_baseline_day("12-15")
pilot_april <- build_snodas_baseline_day("04-15")
```

Review the spatial pattern, valid-year counts, and the frequency/SWE
distribution before using these rasters as references for departure maps.
The default `snow_frequency` values are fractions from zero to one; a future
map legend can display them as percentages. The 21-year SNODAS reference is
separate from PRISM's 1991–2020 normal and is too short for a confident
"near-record" label in zero-heavy lowlands.

The first February 15 run completed with all 21 years and **zero additional
screened cells**. All three rasters are single-layer 822 × 1,578 grids on the
same geometry and carry the February 15 reference date. Of the cells with a
publishable median/frequency (at least 15 valid years), 1,147,681 have all
21 years. Frequency spans zero to one, while the largest median SWE is about
24.17 inches. Median SWE is positive in 104,363 cells, but snow frequency is
nonzero in 807,726 cells. This large difference is expected in intermittently
snowy terrain and supports retaining snow frequency as a companion to median
SWE. It is a numerical and spatial plausibility check, not independent
validation of SNODAS or a final public map design.

## Three-date pilot comparison

The December 15 and April 15 pilots also completed with all 21 water years
and zero additional QC exclusions. All three dates have 1,151,152 cells with
at least 15 valid years, of which 1,147,681 have all 21 years. On the common
grid, the following counts use only cells where the output is defined:

| Calendar day | Cells with median SWE ≥0.1 in | Cells with median SWE ≥1 in | Cells with snow frequency >0 | Maximum median SWE |
| --- | ---: | ---: | ---: | ---: |
| December 15 | 74,001 | 20,275 | 609,965 | 9.25 in |
| February 15 | 89,414 | 46,940 | 807,726 | 24.17 in |
| April 15 | 17,392 | 14,871 | 320,297 | 33.86 in |

The broader February snow footprint and smaller April footprint are
seasonally plausible. April's larger maximum is confined to persistent,
high-elevation snow; the maximum alone should not be read as regional snow
coverage. These checks support the pilot calculation, but do not yet settle
whether a centered seasonal window is needed for stable daily reference maps.

## Centered five-day comparison pilot

`build_snodas_window_baseline_day()` adds a separate, optional comparison
without replacing the calendar-day outputs. For each water year, it reads
the target date and two days on either side (up to 105 daily SWE/depth pairs
for 21 years). Each available pair is quality-screened and aligned to the
common grid. NSIDC-documented missing days are recorded in `qc-summary.csv`
as `known_missing`; an unverified day not in that errata list stops the build.
For a cell to contribute that year, at least **three of five days** must be
valid. The year's SWE contribution is the median of its valid daily SWE
values; the year's snow contribution is the fraction of its valid days with
SWE at least 0.1 inch. The final median SWE is the median of those yearly
SWE contributions, and the final snow frequency is the mean of the yearly
fractions. Thus a year contributes once, even if another year has more valid
days. Cells with fewer than 15 contributing years remain hidden.

From the project root in RStudio, run one date first:

```r
source("scripts/load-snodas-climatology-pilot.R")
window_plan <- plan_snodas_window_baseline_day("02-15")
table(window_plan$ready)
window_plan[!window_plan$ready, c("water_year", "date", "known_missing")]
window_february <- build_snodas_window_baseline_day("02-15")
window_february$paths
subset(window_february$qc, excluded_cells > 0)
```

The February plan has **104 ready pairs**: February 14, 2007 is documented
as missing by NSIDC. The default output is in `pilot-centered-05day/02-15/`,
beside—not over—the calendar-day pilot. There is no network request, but the
build screens and aligns 104 local SWE/depth pairs, so it may take noticeably
longer than the 21-pair calendar-day build. Existing window outputs require explicit
`overwrite=TRUE` to rebuild. The next review compares the centered-window
and calendar-day patterns and cellwise differences for December, February,
and April before choosing an operational smoothing policy. February 29 and
the October/May season edges still need explicit policies for a full daily
baseline. No snow map is published by this pilot.

The February 15 five-day pilot completed with 104 processed pairs and one
NSIDC-documented missing day (February 14, 2007). The QC screen excluded
85 cells on February 17, 2015 where SWE exceeded depth; this matches the
earlier season audit. Relative to the February 15 calendar-day pilot, all
1,151,152 eligible cells retained the same sample-year counts. Median SWE
changed by more than 0.1 inch in 13,437 cells, with a mean absolute
cellwise difference of about 0.004 inch. Snow frequency changed by an
average absolute 0.023 (2.3 percentage points); 19,472 cells changed by
more than 0.1 (10 percentage points). The five-day window broadened the
footprint with any historical snow (807,726 to 864,550 cells), as expected
when nearby days contribute. These are magnitude checks, not yet a choice
of the operational baseline: inspect the spatial differences and repeat
the comparison in early and late season.

## Three-date window comparison and baseline choice

All three five-day pilots are complete. December 15 and April 15 each used
all 105 local pairs with no additional QC exclusions; February 15 used 104
processed pairs, one documented missing day, and screened the 85 previously
flagged cells on February 17, 2015. At every pilot date, the window and
calendar-day methods have identical raster geometry, the same 1,151,152
eligible cells, and identical valid-year counts at every cell.

| Date | Mean absolute median-SWE change | Cells with median-SWE change >0.1 in | Mean absolute snow-frequency change | Cells with frequency change >10 percentage points |
| --- | ---: | ---: | ---: | ---: |
| December 15 | 0.0032 in | 6,591 | 1.7 percentage points | 5,348 |
| February 15 | 0.0038 in | 13,437 | 2.3 percentage points | 19,472 |
| April 15 | 0.0013 in | 5,188 | 0.9 percentage points | 650 |

**Working decision:** use the centered five-day, one-effective-sample-per-
water-year method for daily SNODAS median SWE and snow-frequency references.
It modestly smooths day-specific variation without losing the historical
sample size or changing the valid footprint. Keep the calendar-day pilots as
diagnostics. This is a reference-method choice, not approval to label the
21-year record as a long-term normal or to publish percentile/record maps.
Before a full-season build, specify the shorter windows at the October/May
edges, February 29 interpolation, and resumable output/validation rules.

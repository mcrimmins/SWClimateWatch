# SNODAS availability and quality audit (pilot)

This is a **pre-bootstrap assessment**, not a certification that every daily
archive is complete or scientifically sound. The candidate masked SNODAS record
begins **October 1, 2004**, when NOAA began routine snow assimilation, and ends
at **September 30, 2025** for the latest complete water year at the time of this
assessment. It spans water years 2005–2025 (21 years). SNODAS snow baselines
must remain separate from PRISM's 1991–2020 normals.

## Availability

The [NSIDC SNODAS user guide](https://nsidc.org/sites/default/files/g02158-v001-userguide_2_1.pdf)
points to its [masked/unmasked missing-files list](https://noaadata.apps.nsidc.org/NOAA/G02158/G02158_missing_files.txt).
For the 7,670 calendar days in water years 2005–2025, that list flags **15
missing masked archives** and **one SWE archive with erroneous all-zero data**
(July 31, 2005). Four missing days fall in the provisional November–April snow
season: February 14 and March 26, 2007; March 13, 2008; and December 20, 2012.
None of the official entries flag water years 2014–2025, but this list was last
modified in December 2023, so recent dates still need file-level confirmation.

Three deliberately small remote directory probes checked the listing against
the errata: February 2007 had 27 of 28 archives, missing exactly February 14;
February 2017 and February 2025 each listed all 28 dates. These checks do not
establish full-record completeness or guarantee that each tar contains usable
SWE and depth.

`R/audit-snodas.R` parses the masked section only, builds a day-level calendar,
and summarizes it by water year. `scripts/audit-snodas.R` runs offline from the
locally saved NSIDC list and any locally processed grids. It writes
`data/diagnostics/snodas-audit/day-calendar.csv`, `water-year-summary.csv`, and
`local-raster-quality.csv`. From RStudio at the project root:

```r
source("scripts/audit-snodas.R")
snodas_water_year_summary
snodas_local_quality
```

The status `not_flagged` means only that the NSIDC errata list does not flag
that date; it is **not** a verified download or quality pass. Remote directory
probes are opt-in, capped at three months per call, and separated by at least
1.5 seconds:

```r
source("R/config.R")
source("R/snodas.R")
source("R/audit-snodas.R")
snodas_probe_months(as.Date(c("2007-02-01", "2017-02-01", "2025-02-01")))
```

## Resumable full-period directory inventory

The next availability check reads the **monthly directory listings only** for
October 2004–September 2025 (252 months). It does not download any daily tar
archives. `scripts/inventory-snodas-availability.R` checks at most **12 new
months per run**, waits 1.5 seconds between requests, and saves each successful
listing immediately. Restarting skips months already in the cache. From the
project root in RStudio:

```r
source("scripts/inventory-snodas-availability.R")
snodas_inventory_result$remaining
subset(snodas_inventory_month_summary,
       checked & (unexplained_unlisted > 0 | errata_conflicts > 0))
```

Repeat `source("scripts/inventory-snodas-availability.R")` on later runs until
`remaining` is zero; a complete inventory takes 21 twelve-month batches. The
cache and reports live in `data/diagnostics/snodas-audit/`:

- `monthly-directory-inventory.csv`: resumable month-level cache with listed
  archive dates and check time;
- `inventory-day-calendar.csv`: listed, known-missing, unexplained-unlisted,
  errata-conflict, bad-SWE, or not-yet-checked status for each date;
- `inventory-month-summary.csv` and `inventory-water-year-summary.csv`:
  coverage and gap counts without treating unvisited months as missing.
  Unchecked years are marked `NOT_CHECKED` and their counts are `NA`, not zero;
  partially checked years are marked `PARTIAL`.

If a listing cannot be parsed, the run stops without marking that month
checked; previously saved months remain available. A listed tar name still
does **not** prove that the archive contains valid SWE or depth. That requires
the subsequent bounded content and raster-quality sample.

The completed 2004-10 through 2025-09 inventory checked all 252 monthly
directories. Every unlisted daily archive in that period matched the known
masked-file errata; there were no unexplained absent dates or disagreements
with the errata. This is an archive-name check, not a content-quality pass.

## Bounded SWE and snow-depth content sample

`scripts/run-snodas-quality-pilot.R` checks eight dates spanning winter,
spring melt, November onset, the 2013 grid change, the 2014–2019 zero-repair
interval, and a recent snow-free September day. Five daily tar files are
already available locally; **at most three new tar files** (2012-04-15,
2013-11-15, and 2024-04-15) are requested. The downloader retains the SNODAS
per-run cap and 1.5-second-plus-jitter pacing. Each archive must contain a
valid header/data pair for both SWE and depth before processing. Native daily
rasters are saved under `data/processed/snodas/`; the audit compares both
variables on the fixed common grid without changing published maps.

Preview the plan without network traffic from the project-root RStudio
console:

```r
source("R/config.R")
source("R/snodas.R")
source("R/audit-snodas.R")
source("R/snodas-inventory.R")
source("R/snodas-grid.R")
source("R/snodas-quality-pilot.R")
plan_snodas_quality_pilot()[, c("date", "available", "download")]
```

Then run the bounded download and quality assessment locally:

```r
source("scripts/run-snodas-quality-pilot.R")
snodas_quality_report[, c("date", "variable", "valid_fraction",
  "snow_fraction_valid", "max_inches", "negative_cells",
  "saturated_cells", "repair_zero_cells", "swe_exceeds_depth_cells")]
```

The report is saved after every completed date to
`data/diagnostics/snodas-quality-pilot/swe-depth-quality.csv`, so a rerun can
reuse completed downloads and processing. `swe_exceeds_depth_cells`, SWE-only
and depth-only snow cells are **review flags**, not automatic evidence that
either product is wrong. Likewise, this small sample cannot certify the full
daily record, establish a snow climatology, or prove a fixed update lag.

The eight-date local run completed for both variables. On the harmonized grid,
each date had the same valid-cell fraction for SWE and depth (0.885–0.889),
and none had negative values, signed-16-bit saturation, or cells where SWE
exceeded snow depth. The February 2017 repaired output had no remaining zero
values in the flagged repair-mask cells. There were **no SWE-positive/depth-zero
cells**, but positive-depth/zero-SWE cells ranged from 0 to 20,312 among the
sample dates. These cells need a magnitude and spatial check before they are
interpreted as snow-cover disagreement. The sample depth maxima reached about
130 inches; those high-elevation extremes also warrant a map-level spot check.
An additional native-grid check of the three dates with the most
positive-depth/zero-SWE cells (2008-02-15, 2012-04-15, 2025-02-15) found a
median depth of 0.079 inches and a 99th percentile of 0.197 inches on each
date. Their maximum such depths were 0.197, 0.236, and 0.354 inches,
respectively; **none exceeded 1 inch**. The native-grid cell counts are
slightly larger than those in the common-grid report because the latter omits
the fringe cells outside its center-contained footprint. This is consistent
with a shallow-snow/rounded-zero SWE pattern, but the sample does not establish
that every historical date behaves the same way.
The three largest depth maxima examined were 130.0 inches on 2008-02-15,
116.1 inches on 2017-02-15, and 109.2 inches on 2023-03-01. The first two
were nearly colocated around 37.49°N, 106.8°W, with 2,078 and 80 cells above
100 inches respectively; the third lay around 37.60°N, 112.81°W with 26
cells above 100 inches. The supplied 2023 close-up shows its peak embedded in
a broader high-depth area, although the northern edge of the padded crop cuts
off that feature. All three maxima fall **outside Arizona and New Mexico** in
the intentionally padded display footprint. Footprint maxima must not be
reported as Arizona/New Mexico maxima; subsequent regional summaries should
mask to the two state polygons.
The state-masked maxima from the same dates are **112.7 inches** at
106.4462°W, 36.98708°N (2008-02-15), **100.1 inches** at 106.4375°W,
36.98750°N (2017-02-15), and **84.2 inches** at 106.4458°W, 36.91250°N
(2023-03-01). Their clustering in northern New Mexico supports the
interpretation of a recurring high-elevation snow area, but these three
spot checks are not a full-record outlier screen.

## Quality safeguards

- The [NSIDC guide](https://nsidc.org/sites/default/files/g02158-v001-userguide_2_1.pdf)
  documents a small grid-coordinate shift on October 1, 2013 (about 5% of a
  1-km cell in each direction). Historical cellwise comparisons therefore need
  an explicitly chosen common grid, not layer stacking by row/column.
- From October 9, 2014 through October 10, 2019, the guide identifies false
  zero SWE/depth cells. The official
  [repair mask](https://noaadata.apps.nsidc.org/NOAA/G02158/ancillary/SNODAS_Zero_Repair_Mask.tif)
  is in the `ancillary/` directory (not directly at the archive root as the
  guide's text implies). Nearest-neighbor alignment flags 391 cells in the
  padded AZ–NM footprint. On the February 15, 2017 SWE sample, all 391 held
  zero and are now set to no-data in processed output. `process_snodas_date()`
  requires the repair mask for dates in that interval, records its MD5 and
  affected-cell count, and reprocesses if the mask changes.
- The guide warns of spuriously high SWE in some high-elevation cells,
  including the signed-16-bit saturation value of 32,767 mm. The local audit
  reports saturation and negative-value counts; neither appeared in the
  February 2017 or September 2026 SWE examples. This is **not** a full-record
  outlier screen.
- The September 23, 2026 processed SWE/depth files both retain the expected
  88.9% valid footprint. The February 2017 SWE sample has 88.85% valid cells
  after repair, versus 88.88% in the uncorrected source. Missing cells are not
  interpreted as snow-free.

## Common-grid pilot

`R/snodas-grid.R` defines a fixed 1-km lattice using the post-October-2013
SNODAS grid origin. It keeps cells whose centers fall inside the padded AZ–NM
area of interest, yielding **822 rows × 1,578 columns**. Earlier native grids
are moved onto that lattice with nearest-neighbor sampling; this preserves
SWE values instead of interpolating them. The native processed files remain
unchanged. The deliberately center-contained footprint omits a narrow fringe
at the edge of each native crop so that one era does not gain an extra strip
of cells in historical comparisons.

The offline pilot uses six dates spanning both grid eras: February 15 of 2008,
2013, 2014, 2017, and 2025, plus March 1, 2023. Every overlapping SWE value
matched its native source when mapped back to the source grid (maximum
absolute difference: **0 inches**), and the maximum SWE was unchanged on all
six dates. Between 2,163 and 2,400 source cells per sample fell outside the
center-contained common footprint. No aligned pilot had negative or saturated
SWE cells. These are alignment and sample-quality checks, not proof of
full-record completeness or climatology readiness.

From the project root in RStudio, the following reruns this check from local
archives and writes harmonized diagnostic TIFFs plus
`data/diagnostics/snodas-grid-pilot/alignment-metrics.csv`. It makes **no
network requests** and does not modify published maps:

```r
source("scripts/audit-snodas-grid.R")
snodas_grid_pilot[, c("date", "era", "max_abs_roundtrip_difference_inches",
                      "source_cells_lost_on_roundtrip", "aligned_valid_fraction")]
```

## Baseline decision and pilot gates

Water years **2005–2025 are a provisional candidate**, not an approved snow
climatology. At 21 years, empirical tail percentiles would be coarse even
before accounting for missing days and extensive snow-free lowlands. Avoid
calling a cell-level SWE value "near-record" from this short record. A
snow-cover-frequency or anomaly product may be more robust; percentile maps
need a separately specified seasonal window, minimum sample count, tie/zero
handling, and uncertainty language.

The common 1-km grid has a passing six-date pilot, the metadata-only inventory
is complete, and the eight-date content sample passed its initial quality
checks. For a cool-season baseline, **October 1–May 31** is the recommended
download window: it retains early accumulation and late mountain snowpack
without routinely downloading the mostly snow-free summer. Across water years
2005–2025, this window contains 5,108 calendar dates, of which **5,103
archives are listed** and **five are known missing**. The narrower
November–April window has 3,806 dates, 3,802 listed archives, and four known
missing dates; the complete water years have 7,670 dates, 7,655 listed
archives, 15 known missing dates, and one flagged bad-SWE day. These are
directory/errata counts, not verified SWE/depth-file counts. The October–May
scope was provisional until its storage and quality were tested on a
representative water year; the completed baseline status is below.

The first gate was a **single-water-year, resumable October–May bootstrap
pilot**, with measured raw, processed, temporary, and final disk use. It must
preserve missing dates as missing rather than zero snow and check both SWE and
depth quality before any full-period climatology build. Only after that pilot
was the full 21-year archive scheduled. Snow-cover frequency and
absolute SWE/depth are safer first products than extreme percentile ranks.

The WY2024 pilot starts with a local-only preview. From the project root in
RStudio:

```r
source("scripts/preview-snodas-season-pilot.R")
snodas_season_pilot_status
```

If the listed-day count and five-request cap look right, the following runs
**one** capped batch, then processes both SWE and depth for those dates:

```r
source("scripts/run-snodas-season-pilot-batch.R")
snodas_season_pilot_status
```

Each rerun rebuilds the plan from the completed inventory, processed-file
manifest, and local files; missing dates are excluded, and a
downloaded-but-unprocessed batch is processed before further requests. The
status reports cumulative raw and processed gigabytes, but not temporary
processing peak space. Stop after the
first batch to review output and available disk space before continuing.
Because the first chronological batch contains only nearly snow-free early
October days, it must **not** be extrapolated to winter storage. Before more
sequential batches, run a five-date winter-through-May size sample (five new
archives at most) and inspect its per-date raw and processed megabytes:

```r
source("scripts/run-snodas-season-size-sample.R")
snodas_size_sample
```

The WY2024 sample returned raw archive sizes of 13.0, 22.5, 18.0, 13.8,
and 7.9 MiB for December 15, January 15, February 15, March 15, and May 15.
The corresponding cropped SWE/depth pairs total 0.9, 0.8, 0.9, 0.7, and
0.2 MiB. The five raw files average about 15 MiB/day. If full-domain TARs
were retained, a **rough planning scale**, not a storage forecast, would be
about 3.5 GiB raw plus 0.2 GiB processed for one 244-day season, or roughly
75 GiB raw plus 3.5 GiB processed for all 5,103 listed baseline dates.
Snow-year, seasonal, and archive-size variation could materially change
those figures. The workstation had about 229.5 GiB free on C: at this check.

For the **lean historical pilot**, the processed SWE/depth GeoTIFFs are already
cropped to the padded AZ–NM footprint and compressed. The stage and five-date
batch scripts now use a *processed-only retention policy*: after a new
full-domain TAR has been processed, both regional grids are checked against
their manifest source checksum, output checksums, and date metadata before
that **newly downloaded TAR alone** is removed. A failed or interrupted
processing/verification step leaves its TAR in place for recovery. Previously
downloaded TARs are **not** removed automatically. The raw manifest remains
download provenance even when a TAR has been released. On rerun, a valid
processed SWE/depth pair counts as complete without its TAR, so it is not
downloaded again. In the status table, `processing_pending` is the work
remaining; `raw_pending` means the full-domain TAR is absent, which is
expected under this policy. A future change to processing rules may require
re-downloading historical TARs. Peak temporary extraction space and final
climatology outputs still need measurement. The WY2024 pilot measured one
year's actual footprint before the remaining years were downloaded.

To continue WY2024 without manually invoking the five-date script dozens of
times, one **stage** runs at most four five-request batches (20 archives
maximum), processing SWE and depth after each batch and then releasing newly
downloaded full-domain TARs. Requests retain the
1.5-second-plus-jitter pacing, including a pause between batches. It is
resumable and does not touch the PRISM update or published maps:

```r
source("scripts/run-snodas-season-pilot-stage.R")
snodas_season_pilot_status
```

Review each stage's counts and disk use before rerunning. The stage is a
bounded local pilot, not permission to bootstrap every water year.

The completed WY2024 pilot has **244 of 244** listed dates processed for both
SWE and depth, with no known missing archives. Its compressed regional grids
occupy **113.1 MiB**. The **162.7 MiB** of retained raw TARs are older cached
files; the lean stages kept that amount unchanged while processing the rest.
One year is not enough to forecast the full baseline precisely; scaling this
particular processed footprint to 21 years would be about 2.3 GiB before
climatology products, but interannual snow and file-size differences matter.

Before expanding the historical bootstrap, run the **offline full-year grid
audit** from RStudio. It checks every date's SWE and depth rasters for matching
geometry, time stamps, valid footprint, negative/saturated values, and cells
where SWE exceeds depth. It saves each completed date to
`data/diagnostics/snodas-audit/wy2024-grid-quality.csv` and resumes after an
interruption. It makes no network requests and does not rebuild maps:

```r
source("scripts/audit-snodas-season-pilot.R")
snodas_season_audit$summary
```

The expected finish is `audited_dates == 244`, `pending_dates == 0`, and
`geometry_variants == 1`; any flagged dates or abrupt valid-footprint changes
need review before using this year in a climatology. Retained pre-pilot TARs
can be considered for a separate, previewed cleanup **after** this audit,
not as a side effect of it.

Geometry variants use exact row/column counts and a 1e-9-degree tolerance for
saved origin and resolution coordinates. This ignores GeoTIFF floating-point
roundoff while still flagging a real grid shift. For example, WY2006 initially
appeared to have two variants solely because its saved northern edge differed
by 1e-13 degree after March 29, 2006; with the tolerance it has one variant,
zero pending dates, and zero quality flags.

The complete WY2024 audit returned **244 audited, zero pending, zero flagged,
and one geometry variant**. The valid-cell fraction was exactly 0.8887579 on
every audited SWE and depth grid. The padded-footprint maxima were 45.16 inches
SWE and 95.39 inches depth on May 29, 2024. State masking placed both maxima
inside northern New Mexico, near 105.44°W, 36.64°N. SWE and depth at that
location rose through spring (about 14.0/44.1 inches on March 15,
30.9/76.8 inches on May 1, and 45.2/94.6 inches on May 29), so these high
values are not isolated one-day spikes. This is an internal-consistency
check, **not independent validation** of the high-elevation snow magnitude.
At that stage, the next gate was a lean, resumable year-by-year baseline plan
with the five known missing dates preserved as missing; no full-period
download had been started by the WY2024 audit.

## Year-selectable overnight bootstrap

`R/snodas-baseline.R` provides the long-running October–May baseline runner.
It accepts **explicit water years from 2005–2025**; there is no implicit
full-record download. The completed monthly inventory determines the listed
dates, and the NSIDC masked-file errata preserve known missing days as
missing, never as zero SWE or depth. A year is skipped only when **both**
regional SWE and depth grids are present for every listed date and agree with
the processed manifest. Thus a released full-domain TAR is not mistaken for
missing work. Cached TARs left by an interrupted run are processed before new
requests. Previously retained TARs are not deleted; newly downloaded TARs
are released only after pair verification, as in the WY2024 pilot.

Preview selected years from the project-root RStudio console; this makes no
network requests or changes:

```r
source("scripts/load-snodas-baseline.R")
plan_snodas_baseline(2005:2007)[, c(
  "water_year", "listed_dates", "known_missing_dates",
  "paired_processed", "processing_pending", "processed_mb"
)]
```

For an overnight run from the **RStudio terminal** at the project root:

```text
Rscript scripts/run-snodas-baseline.R --preview 2005-2007
Rscript scripts/run-snodas-baseline.R 2005-2007
```

The second command starts the download. A comma-separated choice such as
`2005,2007,2010` is also accepted. Use `--max-stages=4` for a capped first
run; omit it for an uninterrupted overnight run. From the RStudio **R
console**, the equivalent start is:

```r
source("scripts/load-snodas-baseline.R")
snodas_baseline_result <- run_snodas_baseline(2005:2007)
snodas_baseline_result$final[, c(
  "water_year", "paired_processed", "processing_pending", "processed_mb"
)]
```

The runner retains the downloader's five-request batch cap and
1.5-second-plus-jitter spacing; a stage contains at most four batches (20
requests), with at least 30 seconds between stages. A failed stage is retried
up to twice with increasing pauses, then the run stops. Repeating the **same
command** resumes from the processed manifest and cached raw files, without
redownloading completed dates. It writes a progress/error log to
`data/diagnostics/snodas-baseline/overnight-log.csv`. After each finished
year, it runs the offline, checkpointed SWE/depth grid audit and stops if a
date is pending, geometry differs, or a quality flag needs review. An audited
year is not automatically approved as a climatology; snow-frequency, anomaly,
and percentile methods still require separate design and validation.

Keep the Windows machine awake and plugged in for an overnight run. Start
with a small year range, inspect the final `processing_pending` and audit
reports, and then expand the selected range. Running `2005-2025` later will
skip already processed years, including WY2024. The existing raw archives
remain untouched and can be considered for a separate, previewed cleanup.

## Completed baseline and analysis-time quality screen

The local October–May WY2005–2025 bootstrap is now complete: **5,103 of 5,103
listed dates** have both regional SWE and depth GeoTIFFs, with zero processing
pending. Five known missing dates remain missing, not zero. The processed pairs
total about **2.39 GiB**; all 21 water years have checkpointed quality-audit
reports. The full bootstrap did not change the PRISM update or publish any snow
map.

Three dates have localized SWE-greater-than-depth flags: December 19, 2012
(382 cells); February 17, 2015 (85 cells); and April 30, 2015 (12 cells).
The largest SWE-minus-depth difference on either of the first two dates is
about 0.315 inch; all 12 April 2015 differences are about 0.039 inch. No
audited year has negative values, signed-16-bit saturation, or an unrepaired
zero in the official 2014–2019 mask. These are internal-consistency checks,
not independent validation of the SNODAS estimates.

`R/snodas-analysis-qc.R` defines the conservative analysis policy. Before any
historical SWE/depth comparison, load the paired daily grids and require a
matching date and geometry. In the **in-memory analysis copies only**, set
both variables to no-data wherever exactly one variable is missing, either
variable is negative or saturated, or SWE exceeds snow depth by more than
1e-6 inch. The tolerance ignores numeric roundoff, not a physically meaningful
amount of snow. Do not impute or turn these cells into zero; climatology
sample counts must reflect their exclusion. Keep the original processed
GeoTIFFs and audit flags unchanged for provenance and later review. On the
three flagged dates, the screen excludes exactly 382, 85, and 12 cells and
leaves the source file checksums unchanged.

This screening prepares the local record for a *pilot* snow-cover-frequency
and median-SWE baseline. It does not yet approve percentile or near-record
claims from the 21-year, zero-heavy SNODAS record.

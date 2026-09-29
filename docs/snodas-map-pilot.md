# Unpublished SNODAS winter map pair

This pilot renders two **local PNGs only** for February 15, 2025. It does
not add a snow product to the website, map catalog, or daily updater.
The pair uses the existing Southwest map footprint, state/county/tribal
boundary hierarchy, cities, and compact institutional footer.

- **Observed SWE:** the screened regional SNODAS snow-water-equivalent
  snapshot, in inches, aligned to the common 1-km comparison grid. Zero is
  a pale neutral color; positive SWE progresses through blue and purple.
- **SWE departure:** observed SWE minus the centered-five-day WY2005-WY2025
  median SWE for February 15, in inches. Brown/orange means less SWE than
  the reference median; blue/purple means more. White is near zero.
  No-data cells remain distinct from zero-SWE cells. This is an absolute
  difference, **not** a percentile rank or percent of median.

The sample date is **within** the reference period, so its own water year
contributes to the median. This is suitable for testing layout and
interpretation, not an independent historical ranking. On this date,
observed SWE ranges from 0 to about 18.27 inches and departure from about
-14.25 to +5.51 inches. **Categorical is now the pilot default.**
The optional continuous version uses fixed 0-40-inch observed and
-24-to-+24-inch departure scales for comparison across dates. Values beyond
those continuous limits are shown at the end color; the underlying data
are unchanged.

From the project root in the RStudio console:

```r
source("scripts/load-snodas-map-pilot.R")
snow_preview <- build_snodas_swe_map_pilot(overwrite = TRUE)
snow_preview$paths
snow_preview$qc
snow_preview$review
```

Open the two PNGs in
`data/diagnostics/snodas-map-pilot/2025-02-15/` using RStudio's Files pane.
The function refuses to replace existing pilot images unless
`overwrite = TRUE` is explicit. It screens the original SWE/depth pair
in memory and does not rewrite either source grid. Compare the prominence
of mountains, visibility of zero-snow areas, city-label placement, and
whether the departure legend makes negative and positive values intuitive.
Only after that visual check should the maps be adapted for the cool-season
daily site update. A seven-day SWE-change map remains a separate next
product.

The first local render completed both PNGs. The observed 2025-02-15
SWE/depth pair had **zero QC exclusions**. Visual inspection confirmed the
snow signal is concentrated in higher terrain, zero-snow areas remain
quiet, the boundary/city hierarchy remains legible, and the color bars have
numeric tick labels. These are design checks, not independent validation
of SNODAS against snow observations.

## High-SWE extent and categorical comparison

The February 2025 sample is not sufficient to choose upper legend breaks.
The read-only high-SWE audit checks May 19, 2005; February 15, 2017; and
February 15, 2025. For each anchor date it screens the paired SWE/depth
grids, counts cells and area above 12, 20, 30, and 40 inches, measures the
largest connected patch, and checks the **same cells** during the seven days
before and after the anchor. A cell is called persistent here when it has
valid data on at least 75% of available days and exceeds the threshold on
at least 75% of its valid days. This is a spatial/temporal diagnostic, not
a claim that the SNODAS estimate is physically correct.

The local audit found that on February 15, 2017, **4,933 screened cells**
(about **3,376 km²**) had SWE of at least 20 inches. About **80%** of those
cells met the 15-day persistence criterion. In contrast, February 15, 2025
had no screened cells above 20 inches. The May 2005 example includes much
higher, persistent values in parts of the northern footprint. Those should
not set the legend ceiling on their own: the
[NSIDC SNODAS user guide](https://nsidc.org/sites/default/files/g02158-v001-userguide_2_1.pdf)
warns of erroneously high modeled SWE in some high-elevation areas.

The default **categorical** pilot maps use fixed bins across dates:

- Observed SWE, inches: `<=0.1`, `0.1-1`, `1-2`, `2-4`, `4-8`, `8-12`,
  `12-20`, `20-30`, `>30`.
- SWE departure from the centered-five-day median, inches: `<=-16`,
  `-16--8`, `-8--4`, `-4--1`, `-1-1`, `1-4`, `4-8`, `8-16`, `>16`.

These are display bins only; the source and departure rasters keep their
numerical values. The first observed category includes zero and trace SWE;
missing data remains distinct. The `>30` and `>16` classes are open-ended
in interpretation, even though the plotting implementation caps colors at
90 inches. Categorical versions have a `-categorical.png` suffix and live
beside continuous versions. Both styles were rendered for February 15,
2017, and February 15, 2025; none is added to the public site.

Each pilot render also writes `quality-review.csv` alongside its PNGs.
It also writes `quality-gate.csv`, which distinguishes PASS, REVIEW, and
FAIL. A map with no valid observed/reference overlap fails; high modeled SWE,
paired-cell exclusions, unusually low observed coverage, or low reference
overlap require review. The provisional coverage and overlap thresholds are
80%. Only a PASS can enter a future public-map publication step; a REVIEW
does not alter the saved data or prevent an unpublished diagnostic PNG.
The review flag turns on if screened observed SWE **or its median reference**
has any cells at or above **50 inches**. This is a provisional attention
threshold, **not** an official SNODAS validity limit or a reason to remove
cells automatically. The screening step excludes only documented pairwise
invalid/missing values; no valid high-SWE cell is clipped in the stored
data. The map legend groups high values but the review summary preserves
their actual maxima and counts. A pilot render with a review flag should
not be published without checking the affected locations and local context.

Proposed text below an eventual public SWE map: “SNODAS is a modeled estimate
of snowpack water. Some high-elevation peaks may be overestimated; the
highest color classes are open-ended, and blank areas indicate unavailable
data rather than zero snow.” For the departure map, add: “This is an
absolute difference from the WY2005-WY2025 centered-five-day median, not
a percentile or percent of normal.” Keep these interpretation notes below
the map rather than crowding the map footer.

In the RStudio console, to reproduce the audit and intentionally replace
the local comparison PNGs:

```r
source("scripts/audit-snodas-high-swe.R")
source("scripts/load-snodas-map-pilot.R")
ordinary <- build_snodas_swe_map_pilot(
  as.Date("2025-02-15"), scale_type = "categorical", overwrite = TRUE
)
snowier <- build_snodas_swe_map_pilot(
  as.Date("2017-02-15"), scale_type = "categorical", overwrite = TRUE
)
ordinary$paths
snowier$paths
```

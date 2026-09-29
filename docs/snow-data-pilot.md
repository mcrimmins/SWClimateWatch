# Daily snow data pilot: SNODAS

This is a feasibility check, not yet a production snow workflow. The University
of Arizona's finalized 4-km SWE archive ends in 2023, so it cannot by itself
support the site's daily updates. The working candidate is NOAA NOHRSC's
[SNODAS](https://nsidc.org/data/g02158/versions/1), distributed through NSIDC.
It provides daily 1-km snow-water equivalent (SWE) and snow depth from October
2003 onward. Current maps and historical comparisons would use this same
product, with a SNODAS-specific reference period rather than the PRISM
1991–2020 period.

## Pilot files and checks

On September 24, 2026, we downloaded the masked national daily archives for
March 1, 2023 (a deeper snowpack example), February 15, 2025 (a sparser winter
example), and September 22, 2026 (the latest local PRISM observation date at
the time of the check). A September 23 SNODAS
archive was also available, so a snow update may be ahead of PRISM; joint maps
must use the latest date **common to both products**. The files are kept under
`data/raw/snodas/pilot/`, which Git ignores.

Run the local inspection from the project root in RStudio:

```r
source("scripts/pilot-snodas.R")
snodas_pilot_summary
```

| Date | Daily archive | AOI cells | Valid cells | Snow among valid SWE cells | Maximum SWE | Maximum depth |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 2023-03-01 | 24.07 MiB | 1,299,517 | 88.9% | 13.0% | 38.90 in | 109.17 in |
| 2025-02-15 | 26.56 MiB | 1,299,517 | 88.9% | 14.0% | 18.27 in | 54.13 in |
| 2026-09-22 | 2.91 MiB | 1,299,517 | 88.9% | 0.0% | 0 in | 0 in |

To render the map previews locally, run:

```r
source("scripts/preview-snodas-pilot.R")
```

This writes five PNGs under `data/diagnostics/snodas-pilot/`: 1-km SWE for both
winter dates, 1-km depth for February 2025, February SWE aggregated to the
PRISM grid, and a Tucson-label comparison. They are diagnostic images, not site
products. The approved map treatment places Tucson's label southwest of its
marker and uses a 60%-opaque white backing for city labels. It is now the
default for **future** PRISM and snow renders; existing published PNGs are not
rewritten automatically. The 1-km SWE maps
retain mountain detail that softens on the PRISM grid. On both example dates,
most lower-elevation cells have no snow; the white no-snow field and existing
county lines compete visually. A final snow map may need a more legible
low-end color ramp and slightly quieter county lines while keeping the
established state/county/tribal hierarchy.

The pilot AOI is the configured padded AZ–NM bounding box. Its SNODAS tile is
1,579 × 823 cells at 0.00833333° resolution, compared with the local PRISM
grid's roughly 0.04166667° resolution. Both are longitude/latitude WGS84, but
their pixel edges and extents differ. They must be deliberately resampled or
aggregated to a common template for joint analysis, not compared cell by cell
as-is. The February sample has 1.10 inches SWE near Flagstaff and zero near
Phoenix, a useful basic check on grid orientation. No maximum-value overflow
cells were found inside this AOI on either pilot day.

## Interpretation and processing safeguards

- SWE and depth are **06:00 UTC snowpack snapshots**, not 24-hour snowfall
  totals. For Arizona, 06:00 UTC is 23:00 MST on the previous calendar date.
  PRISM's daily precipitation date does not imply the same observing window.
- The signed 16-bit grid uses big-endian storage. The header specifies meters
  divided by 1,000, so stored integers represent millimeters; divide by 25.4
  to display inches. The no-data code is `-9999`, never zero.
- The masked product has no data in roughly 11% of this padded rectangle,
  including area outside the US domain. Do not display those cells as snow-free.
- Before building a climatology, audit missing days and known SNODAS quality
  issues. The [user guide](https://nsidc.org/sites/default/files/g02158-v001-userguide_2_1.pdf)
  documents occasional spuriously high SWE and a 2014–2019 erroneous-zero mask
  near water bodies. The processor now applies the supplied repair mask and
  refuses to process affected dates without it. See the
  [availability and quality audit](snodas-availability-audit.md).
- SNODAS begins in 2003, but routine snow assimilation began in October 2004,
  so snow ranks cannot use the site's PRISM 1991–2020 baseline. Complete water
  years from 2005 onward are candidates, subject to the completeness audit.
  In the seasonally snow-free lowlands, zero-heavy
  distributions need explicit treatment; a simple percent-of-normal SWE map
  would often be undefined or misleading.
- NSIDC's SNODAS archive has [Basic support](https://nsidc.org/data/user-resources/data-announcements/user-notice-level-service-update-data-products).
  A delayed or missing snow file should not block the PRISM update.

## Single-day download and processing pilot

`R/snodas.R` now provides a separate, capped workflow. NSIDC's documented
public delivery is one national tar per day, with the daily SWE and depth
files inside; it does not offer a documented geographic-subset endpoint for
this product. The processor crops to the padded AZ–NM footprint locally. This
workflow is **not yet connected to** `R/update-data.R` or the published site.

From the project root in RStudio, run this **one-day** test before increasing
the date range:

```r
source("R/config.R")
source("R/snodas.R")
snow_date <- as.Date("2026-09-22")
snow_plan <- plan_snodas_download(snow_date)
preview_snodas_download(snow_plan, max_requests = 1L)
snow_download <- download_snodas_plan(snow_plan, max_requests = 1L)
snow_processed <- process_snodas_date(snow_date, variables = "swe")
snow_processed
terra::rast(snow_processed$path[1])
```

The request cap is five dates per run, with at least 1.5 seconds between
requests plus up to 0.5 seconds of jitter. Existing nonempty raw archives are
skipped unless `plan_snodas_download(..., refresh = TRUE)` is requested.
Downloads use temporary files, verify the expected SWE data/header pair, and
record source URL, size, and MD5 in `data/raw/snodas/manifest.csv`. Processed
GeoTIFFs and their source hash, valid time, no-data fraction, and output hash
are recorded in `data/processed/snodas/manifest.csv`. The header date and
units, binary cell count, and source no-data code are checked before writing.
An unchanged source/output pair is not processed again. Depth is available by
setting `variables = c("swe", "depth")` in the processing call.

The first live check succeeded on September 24, 2026: the September 23 masked
archive was 3,409,920 bytes, its SWE and depth headers both reported
`2026-09-23 06:00 UTC`, and each AOI grid had 823 rows × 1,579 columns with
88.9% valid cells. The SWE maximum was 0.079 inches. Rerunning SWE processing
skipped the unchanged source. A first attempt inside the restricted development
sandbox could not connect; the same request succeeded with network access.

The initial [availability and quality audit](snodas-availability-audit.md)
recommends water years 2005–2025 only as a **provisional** baseline. SNODAS
failures must remain independent of PRISM daily updates. No historical snow
climatology or public snow map has been built. The October–May bootstrap has
since completed; see the availability audit for its quality screen and
remaining climatology decisions.

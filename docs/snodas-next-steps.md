# SNODAS remaining work

## Current-season readiness and remaining operations

The October-May downloader, regional SWE/depth processing, and
WY2005-WY2025 daily reference are ready for manual use starting October 1,
2026 (WY2027). `source("scripts/update-snodas.R")` now also selects the
latest *verified processed* date within WY2027, builds observed SWE and
departure from the centered-five-day median, applies the map-quality gate,
and stages a dated [Current Snow](../site/pages/current-snow.qmd) page with
two PNGs only on `PASS`. Missing or screened cells remain distinct from
zero snow. If no current archive has posted yet, the page shows a waiting
state; `REVIEW` and `FAIL` do not silently replace the prior approved map.
The historical peak-SWE/snow-covered-day archive is a separate workflow.

The standalone snow script is **manual local-site readiness**: it does not
render Quarto or deploy to S3. A separate
[`daily-update-and-publish.R`](../scripts/daily-update-and-publish.R) entry
point now runs PRISM and SNODAS together, renders, validates, and syncs changed
site content. It is now scheduled on the production VM; the October 21, 2026
live publication reported verified snow through October 21. Laptop pilot
work does not change that VM checkout or cron job. Still add a deliberate
policy for detecting later NSIDC revisions
to already processed dates; the current directory inventory cannot reveal
changed archive contents. The first October run may find no posted data.

## Local pilot: seasonal snow anomalies

Add an end-of-season anomaly companion to the Historic Years snow cards. The
first candidate is **seasonal peak-SWE departure** (inches): at each grid cell,
subtract the median of the WY2005-WY2025 *seasonal peak SWE values* from that
year's October-May peak SWE. Compute the median from one QC-screened peak per
water year; do not use the daily calendar-date SWE median for this product.

Before publishing, decide and document minimum valid-year support, treatment
of years with missing days, and how to display the widespread zero-median
lowlands. Test the distribution and legend on both low- and high-snow years,
and reuse the seasonal peak-QC rules. Consider snow-covered-day departure as
a separate persistence measure. A seven-day change in current SWE is another
distinct monitoring product, not a seasonal anomaly.

An isolated pilot now uses the completed seasonal archive rasters. From the
project root in the laptop RStudio Console:

```r
source("scripts/run-snodas-seasonal-anomaly-pilot.R")
snodas_seasonal_anomaly_pilot$summary
```

Outputs stay in `data/diagnostics/snodas-seasonal-anomaly-pilot/`. No daily
downloads, historic-page staging, live updater edits, or S3 writes occur.

Pilot method settings (subject to review before publication):

- Fixed WY2005–WY2025 reference, one October–May peak per year; target years
  within that period are included in the reference (not leave-one-out).
- Require 95% valid seasonal daily coverage at a cell, in both each reference
  year and the target year; require at least 18 of 21 eligible reference years.
  The archive itself accepts 90%, so this pilot additionally masks cells below
  95%; it does not replace or rewrite the archive grids. Missing days are not
  filled, and even an eligible peak could underestimate the true maximum if
  the missing dates coincided with its actual peak.
- Retain existing paired-data exclusions and documented peak masks by reading
  the already screened seasonal peak rasters. Verify peak/coverage/quality
  checksums against each completed archive marker before use. Archive `FAIL`
  is blocked; `REVIEW` is retained with its existing reasons in the source
  inventory, not silently relabeled as clean.
- Subtract the median seasonal peak in inches; never divide by the median.
  A zero-median cell is valid, while missing or insufficient-support cells stay
  missing. Near-zero departures use the existing snow departure category
  (−1 to +1 inch), not a percent or historical rank.
- Compare WY2005, WY2018 and WY2024 on the same categorical brown–white–blue
  scale. Review support counts (`sample_years.tif`) and source cautions
  (`source-inventory.csv`) alongside `pilot-summary.csv` and the map PNGs.

### Companion: percent of median seasonal peak SWE

The same pilot command now also creates `wyYYYY-peak-swe-percent-median.png`
and its GeoTIFF for each example year. Calculation is **100 × target seasonal
peak / median seasonal peak**, using the same 95% seasonal coverage and minimum
18-year reference support as the inch-departure product.

- Calculate a percentage only where median seasonal peak SWE is at least
  **1 inch**. This is an explicit pilot display threshold, not a validated
  universal cutoff. Configure it with `minimum_median_inches`.
- A valid zero target over a qualifying median is **0%**, not missing.
  A median below the threshold (including zero) produces no ratio. Those
  supported low-median cells are gray, labeled “Typical peak <1 inch.”
- Missing target data, inadequate target coverage, or insufficient reference
  support take priority and use the separate beige “Unavailable” category.
  No low-median label conceals a missing target. The saved
  `wyYYYY-percent-display-status.tif` codes are 1=percentage,
  2=low reference median, 3=unavailable target/reference support.
- Fixed categories are <50%, 50–75%, 75–90%, 90–110%, 110–125%,
  125–150%, 150–200%, and ≥200%. Intervals include their lower endpoints.
  The upper category is open-ended; valid numeric percentages are **not capped**
  in the GeoTIFF or summaries. This is percent of median, not percent departure:
  100% means equal to the median; 200% means twice the median.
- Inch departures remain available where the percentage is withheld solely for
  low typical snowpack. Existing archive maps and QC source grids are untouched.

Example for a sensitivity check without rendering:

```r
source("scripts/load-snodas-seasonal-anomaly.R")
snow_percent <- build_snodas_seasonal_anomaly_pilot(
  minimum_median_inches = 0.5, render_maps = FALSE,
  output_dir = "data/diagnostics/snodas-seasonal-anomaly-percent-sensitivity"
)
```

### Local daily comparison pilot

Daily percent-of-median SWE and seven-day net change have a separate
cached-input pilot and are now wired into the local Current Snow workflow.
The VM will not use them until this code is tested and promoted:

```r
source("scripts/run-snodas-daily-comparison-pilot.R")
snodas_daily_comparison_pilot$summary
```

It renders March 1, 2023, April 15, 2024 and February 15, 2025 under
`data/diagnostics/snodas-daily-comparison-pilot/`. Change the dates via
`build_snodas_daily_comparison_pilot(dates = as.Date(...))` after sourcing
`scripts/load-snodas-daily-comparison-pilot.R`.

- Daily ratios use the existing WY2005–WY2025 **centered-five-day daily**
  median, not the median seasonal peak. That reference summarizes each year
  first, so years receive equal weight. The cached reference's built-in 15-year
  minimum remains unchanged; this pilot additionally requires 18 usable years
  using its saved sample-year grid. The same 1-inch median guard, navy ≥200%
  category and gray low-median/beige unavailable categories apply. Daily
  reference labels say “Typical SWE,” not “Typical peak.”
- Observed daily SWE uses verified processed SWE/depth pairs, paired screening
  and common-grid alignment. A single day does not use the seasonal 95%
  coverage rule. Missing/flagged cells remain missing.
- Seven-day change is SWE on date D minus SWE on **exactly D−7**. Both endpoint
  dates, geometry and processed-pair checks must pass. It is net modeled
  snowpack change, **not snowfall or melt alone**. It does not require all six
  intermediate dates. No earlier available date is substituted for D−7.
- If the prior endpoint is absent/unverified, the percent map can still be
  produced, but no change map is shown. The summary records the reason and
  stale pilot change outputs for that exact date are removed. No live maps,
  source grids, or historic cards are changed.
- Change colors show brown for net loss and blue for net gain, with a neutral
  interval of −0.25 to +0.25 inch. Categories use lower-inclusive boundaries;
  exact +0.25 enters the positive 0.25–1 category. Values outside ±4 inches
  use open-ended classes, not clipped data. Historical percentile products
  remain deferred.

### Current Snow integration

`scripts/load-snodas-current-site.R` loads the operational adapter. The existing
daily publisher stages observed SWE, absolute departure, percent of median,
and (when available) exact seven-day net SWE change. No new downloads or
reference builds are added. The first upgraded run rebuilds the current cards;
subsequent runs reuse checksum-verified outputs until inputs or rendering code
change. Arrival or revision of the prior endpoint invalidates reuse too.

The existing current-map PASS gate remains required. The prior endpoint also
needs a verified SWE/depth pair, at least 80% valid regional cells, no paired-QC
exclusions, and no SWE at or above the existing 50-inch review threshold.
At least 80% shared valid coverage is required for the change map. An unavailable
or quality-held prior endpoint removes the old change PNG and displays an
explicit dated explanation instead; it does not block the other three maps.
This does not introduce a blanket outlier mask or a new manual archive review.
Rendered-page validation checks all required images, their full-resolution
links, the latest date and the exact comparison endpoints before S3 sync.

For a local cached-data-only refresh (no download, render or upload):

```r
source("scripts/load-snodas-current-site.R")
snow_plan <- plan_snodas_daily_update()
snow_site <- update_snodas_current_site(snow_plan)
snow_site$status
```

Then render with `quarto render site/pages/current-snow.qmd` from the project
root and preview the local site. This may show a date older than today when
the laptop cache has not been refreshed. Seasonal anomaly cards remain pilot
outputs, not Historic Years additions. SNODAS revision detection is separate work.

To run calculations without rendering maps:

```r
source("scripts/load-snodas-seasonal-anomaly.R")
snow_anomaly <- build_snodas_seasonal_anomaly_pilot(render_maps = FALSE)
```

The baseline is an internal 21-year SNODAS reference, not a 30-year climate
normal. It uses the archive snapshot provenance and does not re-download old
source archives to discover revisions. Coverage/sample-support sensitivity and
legend review precede any decision to add these cards to Historic Years. Carry
forward already accepted archive cautions; this pilot does not require a new
pixel-by-pixel approval exercise. Snow-day departures and weekly SWE change
are not implemented by this pilot.

# Daily regional climate references: local review

Local development only. The user runs this first full build; no daily-runner,
page, staging or production changes are enabled. No source downloads are made.

## Map set

Each metric has five maps: Annual (January–December), Winter (January–March),
Spring (April–June), Summer (July–September), Fall (October–December).
Together these add 25 maps to the already reviewed annual/seasonal totals,
mean temperatures and seasonal precipitation shares.

| Metric | Definition |
| --- | --- |
| Wet days | Mean count of days with precipitation ≥0.04 inch |
| Average precipitation per wet day | Sum of precipitation on wet days divided by their count, pooled across the reference years |
| Heavy-precipitation days | Mean count of days with precipitation ≥1 inch |
| Freeze nights | Mean count of nights with daily minimum temperature ≤32°F |
| Hot days | Mean count of days with daily maximum temperature ≥90°F |

Thresholds are absolute, not local rarity or impact classifications. A one-inch
day is more unusual in some climates than others; a hot-day count at 90°F does
not describe heat risk. These are PRISM grid estimates, not station records.
Freeze counts are not first/last-freeze dates. Percentile-based event thresholds
and dry-spell distributions remain separate future possibilities.

## Run from the laptop project root in RStudio

```r
# Optional preflight: checks local files without building or downloading.
source("scripts/plan-regional-daily-reference.R")

# Main build (includes the same input check).
source("scripts/build-regional-daily-reference-pilot.R")

# Independent check at eight locations, all 25 products.
source("scripts/check-regional-daily-reference-pilot.R")

# Open the standalone local gallery.
source("scripts/serve-regional-daily-reference-pilot.R")
```

Gallery: <http://127.0.0.1:8789/>. Keep RStudio running. Full-resolution PNGs
open by selecting the gallery images. Outputs, methods and checks live in
`data/diagnostics/regional-daily-reference-pilot/`.

The first build reads 1,080 monthly stacks of **daily** PRISM data: precipitation,
minimum and maximum temperatures for 1991–2020. It is more work than deriving
seasonal shares from the monthly reference means. No reliable full-build timing
has been measured yet. Input progress appears every 90 files; aggregation progress
appears every three months. Thirty separate year caches allow an interrupted
build to resume. An unchanged rerun verifies hashes and reuses year calculations
and maps. Leave `force=FALSE` unless intentionally rebuilding.

If the input check is incomplete, inspect `input-plan.csv`. The script requires
exact calendar-month daily archives, date-stamped layers, expected native units
and matching processed-manifest checksums. It stops rather than downloading,
guessing substitute dates or using the monthly grids for daily counts.

## Support and safeguards

Counts are calculated for each complete year/quarter, then averaged over all
30 reference periods, with equal weight per year. Actual leap days are included.
All daily observations must be usable at the cell for that period and variable.
Missing, nonfinite, physically invalid or inverted high/low temperature pairs
are withheld, not zero-filled. An invalid precipitation period does not remove
an otherwise supported temperature reference. Annual and seasonal support are
independent. Sample-year TIFFs accompany every metric.

Intensity is **pooled precipitation on wet days / pooled number of wet days**,
not the average of yearly intensity ratios and not precipitation per calendar
day. Require all 30 complete precipitation periods; zero wet days produce an
unavailable intensity, while zero frequency counts remain valid zeros.

All periods within a metric share the same categorical scale; open-ended bins
do not cap saved values. Every PNG labels its threshold, period and units.
Methods, thresholds, input hashes and output hashes control cache reuse.

Twenty-five targeted calculation/style/date assertions passed locally. Date
matching compares ordered calendar-day values, accepting R's integer/double
Date storage differences while still rejecting missing, duplicate or reordered
days. Actual January 1991 date checks passed for all three fields after this fix.
The full build,
rendered map review and 200 independent point comparisons remain for the user's
run; these have not been claimed complete. The independent checker samples the
original daily inputs and recomputes the statistics without calling the builder's
aggregation helpers.

```r
testthat::test_dir("tests/testthat", filter="^regional-daily-reference$", reporter="summary")
```

November 15: the accepted products are integrated into Climate of the Region.
Cached publication checks, stable links and the portable map transfer are ready
for VM staging; see [staging instructions](climate-of-region-staging.md).

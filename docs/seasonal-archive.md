# Historical seasonal archive pilot

The pilot compares WY1998 (1997-98 El Niño) with WY2011 (2010-11 La Niña).
The Historic Years pages themselves use neutral water-year titles and navigation
labels. Each page shows its December-February RONI value near the top with a
color-coded El Niño, neutral, or La Niña label. The labels use the
single-season thresholds of +0.5 and -0.5 degrees C; it does not classify
the entire water year or establish a sustained ENSO episode. Red/orange denotes
the warm range, blue the cool range, and gray the neutral range. Map cards have
one brief interpretive line each and use the full page width without a right
contents panel or breadcrumb. The date span remains under the water-year title;
calculation reference periods are in the map footers and at the end of the page.
Each year has six October 1-March 31 cool-season maps and two October 1-
September 30 full-water-year maps. The cool season is the main ENSO comparison
period for Arizona and New Mexico; full-water-year maps provide context, not a
measure of ENSO's influence. The separate monsoon project covers summer details.

## Eight products per water year

1. Cool-season precipitation total, inches.
2. Cool-season precipitation percentile rank.
3. Cool-season maximum-temperature departure, degrees F.
4. Cool-season minimum-temperature departure, degrees F.
5. Cool-season wet-day-count percentile rank.
6. Cool-season mean precipitation per wet day, inches per wet day.
7. Full-water-year precipitation total, inches.
8. Full-water-year precipitation percentile rank.

A wet day has at least 0.04 inch of PRISM precipitation at a grid cell. The
wet-day-intensity map is blank where no day qualifies. Daily maximum and
minimum temperature are averaged over the cool season, then each is compared
with the mean of its matching 1991-2020 centered-five-day daily normals.

Precipitation and wet-day-count ranks use the same empirical type-8 rank
function as the monitoring maps. The reference is fixed at complete water
years 1982-2025 (44 seasons), including the displayed year. This is longer
than the 1991-2020 temperature-normal period and will not change when new
years are added. A full-season rank is based on 44 seasonal values per cell,
not the 150 seasonally matched daily samples used in some monitoring products;
the smaller sample limits how finely ranks can distinguish years.

The pilot labels use December-February Relative Oceanic Niño Index (RONI):
+2.1 degrees C for DJF 1998 and -1.4 degrees C for DJF 2011. The source is
[NOAA CPC's historical RONI table](https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso/roni/).
The displayed Southwest climate conditions are observations, not effects
attributable solely to ENSO. Before expanding to all years, establish a
versioned ENSO classification table and an explicit rule for seasons that
change phase during October-March. The regional cool-season focus is supported
by [CLIMAS's ENSO summary](https://climas.arizona.edu/sw-climate/enso-and-monsoon).

## Build and review on the local Windows machine

From the project root in the RStudio R console:

```r
source("scripts/build-seasonal-archive-pilot.R")
```

The script uses existing processed PRISM files; it makes no RCC-ACIS API
requests. The first run calculates one reusable precipitation summary for
each WY1982-WY2025 and then builds the 16 pilot rasters, PNGs, and two Quarto
pages. Later runs reuse the yearly summaries and existing pilot images. If
processed inputs are revised, call `build_prism_archive_pilot_maps(overwrite =
TRUE)` after sourcing the script's dependencies, then regenerate the pages.

Summary caches are under
`data/processed/prism/az-nm-pad050/seasonal-archive/reference/`. The 16
analysis grids are under `data/processed/prism/az-nm-pad050/seasonal-archive/wyYYYY/`;
the PNGs are under `site/maps/generated/prism/seasonal-archive/wyYYYY/`.
Pages live at `site/pages/archive/wy1998.qmd` and `wy2011.qmd`.

To render the site from the RStudio Terminal:

```powershell
quarto render site
```

The pilot is intentionally separate from the 51 daily-updated maps. It is a
one-time historical build and is not run by `R/update-data.R`.

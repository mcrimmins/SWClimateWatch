# WY1896–1981 local monthly archive expansion

The user accepted the WY1896/WY1934/WY1977 pilot and selected the remaining
earlier archive on November 19. Scope is all 86 WY1896–1981 pages: 21 monthly
maps per year, 1,806 PNGs. The separate existing WY1982–2025 archive remains
unchanged. Together the two spans would eventually cover 130 years and 2,730
monthly maps, but this local review site contains only the 86 earlier years.

Each page follows the accepted layout: Water year, Cool season, Spring
(April–June), Monsoon (July–September); precipitation totals/ranks and mean
temperature/departures/ranks, plus September SPI-12. Ranks retain the common
retrospective record, temperature departures retain 1991–2020, and SPI retains
the fixed calibration and fit/support guards. Daily-detail and Snow maps are
not fabricated, and no unverified historical ENSO labels are supplied.

Run in laptop R/RStudio, in this order:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")

source("scripts/build-historic-monthly-backfill.R")
source("scripts/check-historic-monthly-backfill-maps.R")
source("scripts/build-historic-monthly-backfill-pages.R")
source("scripts/check-historic-monthly-backfill.R")
source("scripts/preview-historic-monthly-backfill.R")
```

This is a long graphics build followed by an 87-document Quarto render (index
plus 86 pages). Run each step to successful completion. To resume, repeat the
same command: matching completed year/period outputs are reused. The accepted
early-pilot folder seeds all 63 reviewed maps, full-record references and SPI
fit after signature/checksum verification. No new PRISM downloads or writes
to shared operational fits occur. A build-folder lock prevents overlapping
map jobs; the standard preview render uses `--no-clean` so it can be rerun.

Maps, numeric grids and build/check reports:
`data/diagnostics/historic-monthly-backfill`.

Isolated page sources and rendered website:
`data/diagnostics/historic-monthly-backfill-site`.

The last command validates and opens
`data/diagnostics/historic-monthly-backfill-site/_site/index.html`. Its sidebar
groups years by decade. Nothing is added to the live navigation, existing
site archive pages or transferred publication bundle; no S3 upload occurs.
Based on the accepted pilots, allow roughly 5–6 GiB for numeric/cache outputs
and both source/rendered preview images, plus working headroom.

Expected completion:

- Map check: PASS, 86 years, 1,806 monthly maps, zero requests.
- Rendered check: PASS, 86 pages, 1,806 monthly maps, zero daily-detail/Snow maps.

Validation rejects partial/extra year sets and checks saved values against
the full-record matrices, fixed normal and SPI fit; support masks and seasonal
partitions; source/output hashes; all period tabs, image references/checksums
and availability notes. Existing site page/config hashes and publication-bundle
metadata are recorded and checked for unintended changes. A partial subset
used in development cannot pass the full default coverage gate.

Review at least the earliest year, several intervening decades and WY1981;
then choose staging export/integration separately. Existing 44-year publication
helpers still have their original scope and must not be used to publish this
86-year local batch unchanged.

November 19 tooling verification: all 86 year templates and decade-navigation
entries passed the backfill tests (443 assertions). A separate three-year
end-to-end smoke build reused all 63 accepted early-pilot maps (zero builds,
zero requests), passed independent numeric checks, and rendered three pages
with all 63 monthly images and zero daily-detail/Snow images. Protected source
page/config and publication-metadata checks passed. The full 1,806-map batch
still requires user execution and local review.

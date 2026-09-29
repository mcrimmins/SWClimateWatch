# Map design and branding

## Design intent

Operational maps should make the climate signal primary and geographic context
secondary. They use a restrained hierarchy: raster values first, state and
international borders second, selected city labels third, and county, tribal,
river, or transportation context last. County and tribal-area boundaries are
deliberately thin and partially transparent so they do not compete with the
gridded data.

Temperature percentile maps use a fixed 0-100 diverging scale centered on the
50th percentile. Cool tails are blue, warm tails are orange-red, and near-normal
values are light. This fixed scale makes maps comparable through time and should
not be replaced with the multihue precipitation palette used for accumulation
maps.

Observed precipitation maps use fixed duration-specific scales for 1-, 7-, and
30-day totals. Zero precipitation is nearly white; increasing amounts progress
through blue, green, yellow, orange, red, and purple. The fixed breakpoints keep
successive maps comparable. Their footers give the accumulation period because
no climatological reference period is used in an observed-total map.

## Spatial footprint and reference layers

The map displays every non-missing cell in the downloaded PRISM raster rather
than masking the result to Arizona and New Mexico. The rectangular download is
the configured half-degree padded area of interest, so neighboring parts of
California, Nevada, Utah, Colorado, and Texas may be visible. A neutral light
background distinguishes missing cells from low or middle data values.

U.S. state, county, and national boundaries come from the local `maps` R package;
generating a map does not require a boundary download. City labels come from the
curated `southwest_reference_cities()` table. Priority 1 and 2 labels are shown
by default to keep the display legible. Priority 3 communities remain available
for larger specialty maps.

City labels now use a 60%-opaque white backing so colored climate cells show
through more clearly. Tucson's label is anchored southwest of its city marker
with a short leader, keeping it off the Catalina Mountains to the northeast.
Other labels retain automatic collision avoidance. These defaults apply when
maps are next rendered; previously generated PNGs do not change on their own.

Tribal-area outlines are shown faintly on every operational map. The source is
the U.S. Census Bureau's 2025 cartographic American Indian, Alaska Native, and
Native Hawaiian (AIANNH) areas. Census AIANNH geography includes both legal and
statistical entities, so documentation and legends use the precise term
*tribal-area boundaries* rather than implying that every polygon is a
reservation.

The default regional layer retains the largest polygon component for every
named tribal entity plus any additional component of at least 25 square
kilometres. This scale-aware rule retains all 51 entities in the map footprint
while reducing 627 source components to 83, preventing small detached trust-land
parcels from obscuring the climate grid. The complete clipped Census geometry is
preserved at `reference/map-layers/tribal-areas-census-2025-full.gpkg`; the
regional default is `reference/map-layers/tribal-areas-census-2025.gpkg`.

Boundary styling uses a three-level grayscale hierarchy. Tribal-area boundaries
are thin light gray, county boundaries are darker and moderately thicker, and
state boundaries are black and thickest. All are solid lines and none has a
fill. This makes the administrative hierarchy legible while keeping detailed
tribal geography subordinate to the climate field. Major rivers retain their
separate restrained blue treatment on precipitation and hydroclimate products.

Precipitation and hydroclimate maps also show a restrained major-river layer:
the Colorado, Gila, Rio Grande, Pecos, San Juan, and Canadian systems. It is
derived from Natural Earth's 1:10 million river and lake centerlines and stored
at `reference/map-layers/major-rivers-natural-earth-10m.gpkg`. The short list is
intentional: it adds hydrologic orientation without turning regional monitoring
maps into drainage maps.

Interstates I-8, I-10, I-11, I-15, I-17, I-19, I-20, I-25, and I-40 are cached
from the Census Bureau's 2025 primary-roads layer. Comparison maps showed that
roads compete with county boundaries and city labels at this regional scale, so
they remain available for specialty maps but are off by default.

The reference-layer functions are in `R/map-reference-layers.R`. The three local
GeoPackages are versioned with the project so normal map builds make no network
requests. To intentionally refresh them from their documented sources, run:

```r
source(file.path("R", "config.R"))
source(file.path("R", "map-reference-layers.R"))
build_southwest_reference_layers(overwrite = TRUE)
```

Source references:

- [Census 2025 TIGER/Line technical documentation](https://www2.census.gov/geo/pdfs/maps-data/data/tiger/tgrshp2025/TGRSHP2025_TechDoc_Ch4.pdf)
- [Census 2025 cartographic boundary file naming and geography](https://www2.census.gov/geo/tiger/GENZ2025/2025_file_name_def.pdf)
- [Natural Earth 1:10m rivers and lake centerlines](https://www.naturalearthdata.com/downloads/10m-physical-vectors/10m-rivers-lake-centerlines/)

The relevant functions are in `R/map-southwest.R`:

- `southwest_raster_map()` assembles the raster, reference layers, scale, and theme.
- `southwest_state_boundaries()` returns the state context layer.
- `southwest_county_boundaries()` returns county context.
- `southwest_country_boundaries()` supplies the U.S.-Mexico border.
- `southwest_reference_cities()` returns the stable label set.
- `southwest_tribal_boundaries()` returns the cached tribal-area outlines.
- `generalize_southwest_tribal_boundaries()` applies the documented regional
  component rule while always retaining each entity's largest component.
- `southwest_major_rivers()` returns the selected river centerlines.
- `southwest_interstates()` returns the optional interstate layer.
- `configure_southwest_map_context()` controls optional layers for comparison or
  specialty maps.
- `save_southwest_map()` writes website-ready PNG files.

## Product catalog and website navigation

The public map browser uses Quarto's native expandable sidebar. It is generated
from `config/map-products.yml` rather than maintained as a second handwritten
list. The catalog currently contains all 51 public maps: 25 temperature
products and 26 precipitation products, organized under two top-level branches
and 17 topic groups. Each leaf opens a single-map page with a permanent URL,
breadcrumb, short interpretation below the plot, and full-resolution PNG link.
The active branch opens automatically; unrelated branches remain collapsed.
Current Maps expands directly to Temperature and Precipitation, with a Snow
link alongside them; there is no
separate overview page.

The sidebar separates four levels visually: bold main links, rust-colored
Temperature and Precipitation headings on a light tint, medium-weight topic
headings, and smaller regular-weight map links beside subtle vertical guides.
The selected map has a rust inset bar, tinted background, and bold label.
Equivalent light text and muted backgrounds are defined for dark mode, and
keyboard focus keeps a visible outline. The homepage Current Conditions
dashboard links to the catalog-driven map browser.

The homepage is also generated from the catalog. Its ordered
`dashboard.products` list must contain four to six unique, enabled product IDs.
The operational six-card selection uses a two-column grid on desktop and a
single column on small screens: 7- and 30-day mean-temperature percentile
ranks, 30- and 90-day precipitation percentile ranks, current dry-spell
percentile, and water-year precipitation percentile. Images link to their
permanent product pages, and each card retains a full-resolution PNG link. The
latest common PRISM date and 1991-2020 reference period appear once above the
grid rather than being repeated as page prose around every map.

Every catalog entry has a stable ID plus `enabled` and `scale` settings. Setting
`enabled: false` removes the product from generated navigation and removes its
generated source page on the next catalog build. It also prevents that public
map from being rebuilt by `update_enabled_prism_maps()`. Historical rasters and
map images are not deleted. Shared scientific prerequisites remain active when
an enabled companion product needs them; for example, a disabled 30-day total
does not prevent an enabled 30-day percentile map from receiving its current
accumulation raster. The `scale` setting is validated as either `continuous` or
`categorical` and controls the fill scale used during the next map update.

Each product also requires its own two-sentence `description` in the catalog.
The first sentence states the calculation, period, units or threshold, and
historical comparison when applicable. The second explains what high and low
values mean and notes blank or provisional areas when these affect
interpretation. The page generator places this text below the map and uses it
for the page's description metadata; it no longer substitutes a generic topic
summary.
Continuous rendering remains the catalog default, while percentile-based
products opt into categorical rendering. Categorical rendering uses a
horizontal swatch legend with explicit grouped ranges. Percentile maps
use seven classes: exceptionally low (`<=2`), much below (`2-10`), below
(`10-33`), near normal (`33-67`), above (`67-90`), much above (`90-98`), and
exceptionally high (`>98`). These labels describe the tails of the 1991–2020
reference distribution without implying an all-time record; daily and rolling
samples pool a centered five-day window, while water-year ranks use 30 annual
values. Departures, percent-of-normal, percentile change, and freeze timing use
dedicated classes.
Other products derive categorical classes from their existing vetted legend
breaks, so every catalog product can use either display mode.

The display-mode setting changes presentation only. It does not alter source
rasters, climatologies, percentile calculations, or stored numerical values.

`R/map-product-site.R` validates the catalog and dashboard selection, writes the
homepage and enabled product pages under `site/`, removes stale generated pages,
and replaces only the marked Current Maps section of `site/_quarto.yml`. Run it
from the project root:

```r
source(file.path("R", "map-product-site.R"))
build_map_product_site()
```

The Linux rendering entry point performs this step automatically before Quarto
renders the site.

## Publication validation

Every enabled catalog product passes a publication check before deployment.
The validator confirms that the latest PNG is readable and nontrivial, uses the
standard 1998 by 1533 pixel output size, has a byte-identical dated companion,
and is referenced by both its generated page and sidebar navigation. For maps
that should track the latest processed PRISM date, the dated companion must
match that expected date. First-freeze, last-freeze, and freeze-free-season
products use an explicit seasonal-retention policy because retaining the most
recent publishable completed season is intentional.

After Quarto renders, the same check can also verify the HTML page, embedded map
path, and full-resolution download link. Results are written to
`data/diagnostics/map-product-status.csv`; this operational report is ignored by
Git. Any failed enabled product stops the render/deployment workflow.

Run the complete check from the project root:

```r
system2(
  "Rscript",
  c("scripts/validate-map-products.R", "--require-rendered")
)
```

Omit `--require-rendered` when checking source pages before a Quarto render.

`R/map-product-scales.R` resolves each product's configured display mode and
defines the categorical-class library. `southwest_raster_map()` applies either
the continuous color bar or categorical swatches while all product builders
continue to share the same palettes and limits.

## Logo files

The supplied horizontal institutional lockup is stored at
`site/assets/branding/ua-csap-climas-logos-horizontal.png`. Keeping the source
asset in the self-contained site, but separate from generated maps, makes it
available to both Quarto and the R map workflow. Additional partner marks belong
in `site/assets/branding/partners/`.

The horizontal lockup appears below the homepage dashboard and in a compact
white footer appended to downloadable maps. It is not squeezed into the narrow
sidebar and never overlays climate data. `save_southwest_map()` adds this footer
when its `logo_path` argument is supplied; the operational temperature-map
workflow supplies `southwest_brand_logo_path()` automatically. The logo starts
at the map panel's left edge and the two-line attribution ends at its right edge.
The footer lists only the PRISM/RCC-ACIS data source and the 1991-2020 reference
period. The logo uses 23 percent of the exported map width with minimal padding.
The balanced layout exports at 11.1 by 8.05 inches before the footer is appended,
with roughly five-percent side gutters. This keeps the full data footprint and
geographic proportions while giving the map more of the canvas width.

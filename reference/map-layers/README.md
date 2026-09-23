# Southwest map reference layers

These clipped GeoPackages make routine map rendering deterministic and offline.

- `tribal-areas-census-2025-full.gpkg`: complete clipped U.S. Census Bureau 2025
  cartographic AIANNH areas. These include legal and statistical tribal
  geographies.
- `tribal-areas-census-2025.gpkg`: default regional derivative. It retains the
  largest polygon component for every named entity plus detached components of
  at least 25 square kilometres (51 entities and 83 of 627 source components).
- `major-rivers-natural-earth-10m.gpkg`: selected Natural Earth 1:10 million
  river centerlines: Colorado, Gila, Rio Grande, Pecos, San Juan, and Canadian.
- `interstates-census-2025.gpkg`: selected routes from the U.S. Census Bureau
  2025 primary-roads layer. This layer is optional and is not shown on standard
  regional maps.

Rebuild intentionally from the project root with:

```r
source(file.path("R", "config.R"))
source(file.path("R", "map-reference-layers.R"))
build_southwest_reference_layers(overwrite = TRUE)
```

Normal map builds read these files locally and make no reference-data requests.

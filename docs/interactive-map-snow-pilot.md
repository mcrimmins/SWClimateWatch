# Interactive Snow pilot

Local review only. The production daily runner does not build Snow payloads yet. No SNODAS downloads occur.

## Combined Interactive Maps page preview

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/build-interactive-map-snow-site-preview.R")
source("scripts/test-interactive-map-snow-pilot.R")
source("scripts/preview-interactive-map-site.R")
```

Open <http://127.0.0.1:8791/pages/interactive-maps.html> and keep R open. The combined builder refreshes cached PRISM viewer data against the accepted Monthly Climate release, builds the Snow snapshots, then copies both into the source site's Interactive Maps folder. It does not publish or download data. The first rebuild may take several minutes; messages report daily PRISM bundles and Snow dates. Later runs can reuse the base PRISM build.

The regular preview renders the site in place with `--no-clean`, validates the rendered viewer, and reuses the local server if it is already running. For a quicker single-page render, set `options(swc.interactive.full_site = FALSE)` before previewing. Source and rendered validation include compressed byte counts, integrity receipts, exact decoded lengths, field layout, grid geometry, masks, ratio support, derived values, and metric/date links. Snow gzip files are included in the versioned asset inventory and obsolete managed Snow bundles are cleaned up only within the viewer's source folder.

This is the same reviewed Snow selection within the standard site page, including the explicitly labeled historical example. Snow operational refresh, release binding, mobile testing, staging publication and production promotion remain separate steps. The standard automatic PRISM build does not add Snow yet. Use the combined builder above when reviewing Snow.

## Standalone pilot

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/build-interactive-map-snow-pilot.R")
source("scripts/test-interactive-map-snow-pilot.R")
source("scripts/preview-interactive-map-snow-pilot.R")
```

Open <http://127.0.0.1:8794/> and keep R open. The preview reuses its server on repeat runs. To use a different port, set `options(swc.interactive.snow.port = 8795L)` before previewing. Rebuild, then refresh the browser after editing assets. No Quarto render is needed.

The test script first checks the local ignored tools cache (`data/diagnostics/local-test-tools/node.exe` on Windows), then R's PATH, common Windows installation locations, and the installed Codex runtime. This laptop's local cache contains a SHA256-verified copy of the already-installed Codex Node executable, because RStudio could not discover the packaged installation. The executable is not committed or published. Other machines can use their own Node installation or set `options(swc.interactive.node = "C:/path/to/node.exe")` before rerunning the test. A missing Node stops the JavaScript checks explicitly; it does not prevent opening the preview or imply those checks passed.

Choose Current Conditions → Snow → Snowpack water. Metrics: SWE, departure from median, percent of median, and exact seven-day net change. Period chooses an explicitly labeled cached snapshot. Other PRISM modes remain available so selector transitions can be reviewed. Changing modes selects a compatible variable; Snow is only in Current Conditions.

The default dates are the date recorded in the local Current Snow publication report and a cached winter example, February 15, 2025. On this laptop the published snapshot is October 7, 2026, not today's date. Its September 30 endpoint is missing/unverified, so seven-day change is unavailable. The winter example has February 8 and February 15 endpoints. Nothing silently switches dates. For other fully cached October–May dates, set `options(swc.interactive.snow.dates = as.Date(c("2025-02-15")))` before building. Missing/unverified inputs stop the build.

## Payload and mask assessment

- Native grid: 822 rows × 1,578 columns, 1,297,116 cells at 30 arcseconds (approximately 1 km). Native cell geometry is retained for both map drawing and queries.
- One gzip bundle per snapshot holds five Float64 fields (SWE, median, departure, percentage, change) and three byte fields (reference years and two masks). No rounding, coarsening, or interpolation.
- Measured gzip transfer: 0.104 MiB for October 7 and 1.224 MiB for February 15. Decoded bytes: 53.19 MiB per snapshot, plus browser working arrays. These are desktop pilot measurements, not a mobile memory assessment. Browser-native gzip decompression is required; unsupported browsers get a clear message.
- Desktop browser review after merging adjacent same-color drawing spans: initial snow layer ready about 0.68 seconds, page ready about 1.46 seconds, cached winter redraw about 0.78 seconds. Point queries were about 1-3 ms in the initial review. The browser reported about 192 MiB JavaScript heap after switching through Snow, Daily and Monthly views; this is a whole-page measurement, not a snow-only allocation. Retain mobile testing as a release gate. Drawing spans preserve native category boundaries and do not average cells.
- Exactly zero observed SWE is transparent, allowing the basemap to show through. It remains 0.00 inches in point tables and is explicitly labeled in the legend. Small positive SWE stays colored; missing observations remain a separate beige category. Zero departure, percent of median and change retain their meaningful comparison colors. The original paired SWE/depth screening and map quality gate must pass.
- Departure uses the existing median and ≥15-year reference. Gray low-typical cells (median <1 inch) distinguish them from near-median white; their actual supported departure stays in the point table.
- Percent of median preserves the production ratio guards: ≥18 reference years and median ≥1 inch. Low typical SWE is gray; unsupported observation/reference is beige. No division by zero or tiny medians. Gray does not imply no observed snow.
- Change requires exactly date minus seven days, matching geometry, verified screened inputs and ≥80% shared valid coverage. It is net snowpack water change, not snowfall or melt alone.

The assessment CSV is `data/diagnostics/interactive-map-snow-pilot/snow-payload-assessment.csv`. All exported fields undergo full lossless round-trip checks. Node checks also cover every decoded cell, category boundaries, selector transitions and payload truncation. Small R fixtures exercise support thresholds and zero/missing values.

Managed-site copying, receipts, validation and cleanup for gzip bundles are now available for local page review. Before staging publication: review mobile memory and drawing performance; choose production retention/cache limits; implement automatic Snow refresh and bind operational selections to the verified published release. This pilot deliberately does not claim those remaining workflow steps are complete.

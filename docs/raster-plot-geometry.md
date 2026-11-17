# Raster plotting geometry: local investigation

November 17, 2026: the shared `southwest_raster_map()` helper removed missing
cells and handed the remaining centers to `geom_raster()`. Missing entire rows
or columns make inferred spacing unreliable. Uniformly skipped columns can even
produce oversized cells without a warning; a single supported row/column has
no native spacing to infer.

The local cached current PRISM audit covers 63 single-layer fields at the dates
in `map-product-status.csv`. Six raw shared-helper plots reproduced the uneven
horizontal-interval warning. These are sparse freeze fields, including the
first-freeze delay overlay. First/last-freeze published maps already replace
their base layer with explicit-size tiles; they are not four additional broken
published products. The remaining affected published products are:

- Freeze-free season length (`mint_freeze_free_length`).
- Freeze-free season-length departure (`mint_freeze_free_departure`).

The shared helper now uses native-width/native-height tiles when either axis
has gaps, a singleton or no supported cells. Dense complete-axis data keep the
fast raster renderer. Cells and grid extent are not resampled, interpolated,
filled or shifted; colors, classification, references and numerical inputs are
unchanged. Both continuous and categorical branches use the same geometry rule.

## Rebuild and preview locally

Run in R from the project root:

```r
source("scripts/rebuild-raster-plot-review.R")
source("scripts/preview-raster-plot-review.R")
```

Keep R open. The gallery is served at `http://127.0.0.1:8793/`; it can also be
opened directly from `data/diagnostics/raster-plot-review/index.html`. If that
port belongs to another preview, set `options(swc.raster.plot.port=8794L)` before
sourcing the preview script.

The gallery contains seven before/after pairs: both affected products in both
display modes; dense mean-temperature and 30-day precipitation controls; and a
clearly labeled synthetic missing-column example. The baseline shared helper
is read from production commit `1c23270adfe1f17e47ff7f0cb9a4519f20a87f56` using
the local Git repository. No fetch or upstream climate request occurs.
RStudio may have a different PATH from Command Prompt. The review searches
standard Git for Windows installation folders when Git is absent from R's PATH.
For a nonstandard installation, set
`options(swc.raster.plot.git = "C:/path/to/git.exe")` before rebuilding.

Outputs stay in `data/diagnostics/raster-plot-review/`:

- `grid-audit.csv`: raw helper warnings before/after, selected renderer and input hashes.
- `map-review.csv`: rendered warnings, source files and changed-pixel fraction (0–1).
- `summary.csv`: audit counts and unchanged input-grid verification.
- Full-resolution before/after PNGs and the comparison gallery.

Local results: six raw warnings before, zero after; four affected product/mode
renderings have no warnings after the fix. Dense controls are pixel-identical.
All audited input hashes and before/after display data are unchanged. Regression
tests cover missing rows/columns, uniformly thinned axes, single cells, empty
rasters, category preservation, native bounds and floating-point coordinate
roundoff; existing current-temperature/freeze tests also pass.

This step does not overwrite operational PNGs, recompute comparison caches,
update the website or publish. After local approval, regenerate the two affected
products from cached derived grids on staging and validate the usual map pages.
No statistical-cache migration is needed for this rendering-only change.

## Staging rebuild after local approval

The user accepted the local comparisons November 17. Under the staging daily
lock, check out the committed fix, then run:

```bash
Rscript scripts/build-map-product-site.R
Rscript scripts/rebuild-cached-freeze-free-maps.R
Rscript scripts/publish-site-s3.R
cat data/diagnostics/raster-plot-rebuild/status.csv
```

The cached rebuild verifies both existing map/status fingerprints and both
exact dated single-layer derived grids before installing anything. It prepares
both maps without rendering warnings, verifies unchanged input hashes, and
installs the dated and latest PNGs using the configured display mode and usual
branding. It does not call the statistical calculation or cache builders. The
normal publisher revalidates the new images, grouped pages and stable hotlinks
before S3 upload. No laptop PNGs or climate data need transferring. The updated
shared helper also applies to subsequent ordinary daily rendering.

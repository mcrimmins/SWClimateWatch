# Historic seasonal snow anomaly page review

Local review increment, November 13, 2026. Production staging remains unchanged.

Run from the laptop project root in the RStudio console:

```r
source("scripts/run-snodas-seasonal-anomaly-pilot.R")
source("scripts/preview-snodas-historic-anomalies.R")
```

The first script rebuilds the WY2005/2018/2024 companions and their output
checksums from the completed WY2005-WY2025 seasonal archive. The second verifies
output checksums, current source provenance, reference settings and existing
archive triage decisions before copying the full Historic Years pages into
`data/diagnostics/snodas-historic-anomaly-preview/`. It retains PRISM content and
the original two snow maps, adding departure and percent-of-median cards plus
period/reference/display explanations. Quarto renders that separate project;
no standard site sources, seasonal inputs, publication settings or S3 objects
are changed. No source downloads are requested.

Review at <http://127.0.0.1:8784/>. Keep RStudio running while browsing. To reopen
an already rendered preview without rebuilding:

```r
source("scripts/serve-snodas-historic-anomalies.R")
```

Check all three years, image links, four-card organization, small-screen layout,
reference wording, gray low-snow shading and unavailable areas. The percentage
threshold applies to the reference seasonal peak, not the displayed year's
peak. Large departures remain colored in low-median areas. Existing REVIEW
archive status is preserved; the anomaly companions do not certify or remove
source anomalies. The map footers still identify this unpublished pilot.

After local acceptance, separately expand the verified anomaly build to eligible
archive years, remove pilot-only presentation wording, integrate explicit site
staging/publication checks and map-catalog/hotlink registration, then test on
the VM staging site before production promotion. Do not use this isolated
preview directory as the production deployment source.

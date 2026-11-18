# Seasonal snow anomaly archive: local build and staging preparation

November 13, 2026: all eligible completed snow seasons, WY2005-WY2025, are enabled
in `config/snodas-seasonal-anomalies.yml`. This is a release under local review;
production deployment is a separate explicit step.

Local verification completed November 13: all 42 companions built, all 21 years
reused on the second build, the normal site rendered, all 84 snow maps/links
passed, and 42 dated anomaly catalog URLs passed integrity checks. Targeted
archive, cache-repair, publication-order and hotlink tests passed. Expanded
user review and VM staging/production acceptance remain pending.

## Laptop: build and review

From the project root in RStudio:

```r
source("scripts/build-snodas-seasonal-anomaly-archive.R")
table(snodas_anomaly_archive$summary$event)
source("scripts/preview-snodas-seasonal-anomaly-archive.R")
source("scripts/check-snodas-seasonal-anomaly-publication.R")
```

The archive has **42 anomaly PNGs** (two per year). Historic Years pages retain
the original peak-SWE and snow-covered-day maps, for **84 snow images** checked
across 21 pages. The full local site uses the normal navigation. Preview at
<http://127.0.0.1:8785/pages/archive/wy2024.html#snow-season>. Keep RStudio running.
Use `source("scripts/serve-snodas-seasonal-anomaly-archive.R")` to reopen an
already rendered preview without rebuilding. No S3 upload is invoked.

Targeted checks:

```r
testthat::test_dir(
  "tests/testthat",
  filter = "snodas-seasonal-anomaly|snodas-historic-site|deploy-site-s3|map-hotlinks",
  reporter = "summary"
)
```

Run the archive build again to verify cache reuse. It prints REUSED for unchanged
years. The numerical reference and each completed year's maps have checksums;
source/method/display changes invalidate their signatures. A damaged output is
rebuilt. Interrupted builds retain completed-year checkpoints, so rerun the same
command to resume. The first build renders 42 maps; later unchanged checks are
much faster. No new SNODAS daily downloads or input-grid edits are requested.

Check the first/last eligible years, dry/wet examples, full-resolution links,
gray/white distinctions and page explanations. Existing archive REVIEW labels
and documented peak exclusions remain; no new blanket outlier cap is imposed.

## Files and publication

Private completed products and checkpoints:
`data/diagnostics/snodas-seasonal-anomaly-archive/`.
Source seasonal grids remain in `data/diagnostics/snodas-seasonal-archive/`.
The publication build uses normal footer wording, while the original three-year
pilot stays separate and labeled as a pilot.

Staged PNGs use `site/maps/generated/snodas/seasonal-archive/wyYYYY/` with names
`peak_swe_departure.png` and `peak_swe_percent_median.png`. They receive stable
year-specific catalog URLs, without a release hash or a rolling latest alias.
The generated `site/assets/snodas-seasonal-anomalies.json` binds the four images
per year to source provenance and fixed methods. It is ignored by Git and
regenerated in each checkout; commit the configuration, code, page changes and
documentation, not private rasters/checkpoints or generated manifests/PNGs.

Before each normal site render, the publisher calls
`scripts/stage-cached-snodas-seasonal-anomalies.R` to restore the verified four-map
sections after page regeneration/checkout. After render, publication checks
require staged/rendered image checksums, PNG signatures, image and download links,
reference settings and manifest identity. Failure stops upload. Existing current
and PRISM historic validation counts remain separate; this adds a dedicated snow
report at `data/diagnostics/snodas-seasonal-anomaly-publication/{summary,checks}.csv`.
There is no new cron, source acquisition or daily historical recalculation.

## VM staging: prerequisite before publication

After committing/pushing and checking out the accepted laptop commit in the
staging checkout under its existing lock, either transfer the completed anomaly
directory above or run the same archive build using the VM's verified seasonal
archive/triage cache:

```bash
TZ=America/Phoenix Rscript scripts/build-snodas-seasonal-anomaly-archive.R
TZ=America/Phoenix Rscript scripts/stage-cached-snodas-seasonal-anomalies.R
```

Then run the existing site-only staging publication with `staging.env` loaded,
followed by `Rscript scripts/check-snodas-seasonal-anomaly-publication.R`.
The build must precede publication: the enabled feature deliberately refuses to
publish with an absent, incomplete or mismatched cache. Use the established
checkout/environment/lock procedure; do not run concurrent writers. No laptop
data transfer is required if the VM's existing seasonal inputs pass verification.
Production requires a separate approved promotion and the same cache prerequisite.

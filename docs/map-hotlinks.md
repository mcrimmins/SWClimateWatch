# Stable map image links

Production promotion confirmed by the user November 10, 2026, after local tests
and staging review. The supplied staging header check confirmed HTTP 200,
image/png and public,max-age=300,must-revalidate. Deployment instructions below
remain available for future releases.

## Public contract

The catalog is at `maps/catalog.html`, with CSV and JSON at `maps/catalog.csv`
and `maps/catalog.json`. About links to it. It covers published current PRISM,
current snow, monthly climate, historic-season, Daily Explorer and weather PNG
maps, plus a selected synopsis seven-day temperature map. Interactive station
widgets are pages rather than exported PNG maps and are not converted here.

Under the production site base `https://cales.arizona.edu/climate/watch/`:

| Family | Example relative image URL |
| --- | --- |
| Current PRISM | `maps/latest/current/pcpn_percentile_30day.png` |
| Current snow | `maps/latest/snow/swe-observed.png` |
| Monthly temperature | `maps/latest/monthly/temperature-12month.png` |
| Monthly precipitation | `maps/latest/monthly/precipitation-12month.png` |
| Monthly SPI | `maps/latest/monthly/spi-12month.png` |
| Latest daily precipitation | `maps/latest/daily/pcpn-observed.png` |
| Latest daily mean temperature | `maps/latest/daily/tmean-observed.png` |
| Latest 500-mb pattern | `maps/latest/weather/height500.png` |
| Latest jet pattern | `maps/latest/weather/jet250.png` |
| Latest moisture pattern | `maps/latest/weather/moisture.png` |
| Weekly synopsis temperature | `maps/latest/synopsis/temperature-7day.png` |
| Historical seasonal map | `maps/generated/prism/seasonal-archive/wy2024/cool_total.png` |
| Individual daily map | `daily-explorer/maps/2026-10-02-pcpn-observed.png` |

All 1-/3-/6-/12-month products receive latest endpoints. Current map endpoints
use the persistent catalog product ID. Existing original URLs, including
versioned monthly releases, are unchanged; the catalog JSON includes the
original source URL and checksum for provenance. Historical and individual-day
URLs are date-specific; they can reflect a validated source revision for that
same date. They do not become a later observation day.

Latest means the most recent accepted publication for that product, not
necessarily yesterday or a common date across PRISM, snow, monthly and CORe.
The catalog records each known source date/period; consult the standalone map
labels for its complete period, units and baseline. Retained freeze and inactive
snow maps remain dated as such. Source images are not cropped or recalculated.

Unavailable comparisons (including early-water-year three-day maps), disabled
weather, and a synopsis temperature map not selected in the current synopsis
receive a labeled notice PNG at the same latest URL. They do not expose an
unlabeled older map. The endpoint registry at
`data/diagnostics/map-hotlinks/registry.rds` preserves formerly declared rolling
URLs: removed products receive a disabled notice. Keep this small registry with
production diagnostics/backups when migrating machines. Do not delete endpoints
as part of routine cleanup.

## Publication order and cost

Both daily and site-only publication use the common deploy helper. Hotlinks are
created **after all existing rendered validation and optional weather quarantine**,
using the accepted rendered files/manifests. All source/alias checksums are
verified before the first upload. A failed validation stops upload. This does
not introduce climate downloads, calculations, or a separate cron job.

A rolling alias is one reusable PNG copy. Unchanged bytes are not recopied when output is retained; the endpoint registry
also restores unchanged timestamps after render cleanup to prevent unnecessary
S3 uploads. Historical images are cataloged at their original paths without duplication.
The catalog grows as additional accepted days/seasons are published. The laptop
review found 78 rolling endpoints and 639 dated links; those counts describe
that older local cache, not today's production inventory.

`maps/latest/` is synced separately with
`Cache-Control: public,max-age=300,must-revalidate`. The regular site sync excludes
that prefix, so it does not overwrite its cache policy. This requests a five-minute
browser cache; a university proxy/CDN may impose another policy. AWS sync uploads
new/changed files; changing a policy later does not automatically replace metadata
on unchanged objects. Do not promise immediate cache invalidation. Existing
dated-image cache policies are unchanged. See the [AWS sync command reference](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html) for cache-control and unchanged-object metadata behavior. Stable latest endpoints are never
removed by the new alias upload, even if general site deletion is enabled.

S3 sync publishes individual objects, not a transaction across all images.
If a data/validation step fails, the last uploaded versions remain. As with the
existing site sync, a transfer interrupted mid-upload may need a retry.

## Local review

Use the locally rendered site already on disk:

```r
source("scripts/preview-map-hotlinks.R")
browseURL(normalizePath("site/_site/maps/catalog.html"))
```

The script makes no requests and does not upload. Catalog image links resolve
locally for preview; displayed/copyable URLs show the proposed production URLs,
which now have production endpoints. A local preview can still contain older
source dates than production. It verifies image integrity and routing,
not the age of this laptop's cached data. Production retains all its existing
freshness gates. Rerun the preview to verify unchanged alias reuse.

Tests:

```r
testthat::test_dir("tests/testthat",filter="map-hotlinks|deploy-site-s3",reporter="summary")
```

## Staging test after commit/push

Use the usual staging checkout under its daily lock. Load/export staging.env and
confirm the exact watch-staging destination/state directory. Then run
`Rscript scripts/publish-site-s3.R`; it creates and validates the catalog and
aliases automatically. No laptop map transfer is needed. Review:

- `https://cales.arizona.edu/climate/watch-staging/maps/catalog.html`
- A monthly SPI-12 and temperature-12 alias, a current PRISM map, snow, and the
  latest daily/weather examples. Check independent dates and units.
- One archived WY map and one specific daily date.
- Unavailable notices where applicable; weather quarantine must not leak old
  accepted-looking latest images.
- The About link, search, Copy button and CSV/JSON downloads.

Inspect a header from the VM:

```bash
curl -I https://cales.arizona.edu/climate/watch-staging/maps/latest/monthly/spi-12month.png
```

Expect an image response (`Content-Type: image/png`) and check whether the public
response honors the requested cache policy. Test embedding in the external
project after staging approval. Production URLs use `watch/`; staging URLs use
`watch-staging/`. Actual image links only become available after publication.

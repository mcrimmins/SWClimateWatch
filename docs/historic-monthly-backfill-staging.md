# Earlier Historic Years staging release

The WY1896–1981 local build and rendered review passed: 86 pages and 1,806 maps,
zero downloads, zero daily-detail/Snow substitutions. The user accepted the
pages November 19 and selected staging testing. Keep the WY1982–2025 release
separate, preserving its 924 monthly, 176 daily-detail and 84 Snow maps.

The combined site spans 130 years (WY1896–2025) and 2,730 monthly maps. The new
release generates the earlier pages and decade navigation during cached
staging, after the existing archive/Snow reconciliation. Generated earlier
page sources are ignored by Git and rebuilt from the verified bundle; the
original 44 tracked pages stay tracked. Map links automatically includes the
new stable year/season image URLs.

## Laptop

Run in RStudio:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/export-historic-monthly-backfill-release.R")
```

This validates the completed backfill and exports a separate
`data/processed/historic-monthly-backfill-release` folder. It performs a graphics
pass over the verified numeric grids to remove local-pilot footers. No PRISM
downloads, SPI refits, existing-release changes or site uploads occur. Expect
a long first export (1,806 maps); completed matching images are checkpointed
and reused if the same command is rerun. Wait for `Portable backfill READY`.

Commit the early-pilot/backfill modules, scripts, tests and docs, the shared
preview/publication changes, deployment hook, Git attributes/ignores and
roadmap. Exclude unrelated weather/IVT experiments, generated product pages,
root pasted-terminal files, all data caches and map binaries. Push
`codex/historic-monthly-pilot` and record `git rev-parse HEAD`.

In Windows Command Prompt, package with a relative archive filename:

```bat
tar -czf swc-historic-monthly-backfill-release.tar.gz --exclude=*.rds --exclude=export.lock -C data/processed historic-monthly-backfill-release
certutil -hashfile swc-historic-monthly-backfill-release.tar.gz SHA256
scp swc-historic-monthly-backfill-release.tar.gz crimmins@10.222.142.128:/home/crimmins/incoming/
```

Only new publication PNGs and relative-path metadata are transferred. The raw
monthly grids, SPI fits, numeric/reference caches and isolated preview site
do not need transferring. The existing staging VM publication bundle at
`data/processed/historic-monthly-release` must remain present and verified.

## Staging VM

Compare `sha256sum` of the incoming tarball with the laptop digest. Under the
staging daily lock, stash tracked generated site files, stop if any tracked
changes remain, fetch `codex/historic-monthly-pilot`, and detach at the fetched
commit. Compare its full hash with the laptop before continuing.

```bash
bash scripts/test-historic-monthly-backfill-staging.sh /home/crimmins/incoming/swc-historic-monthly-backfill-release.tar.gz
```

The helper loads only staging.env, checks the exact staging destination and
state directory, holds the staging lock, verifies the existing 924-map bundle,
unpacks the backfill and stages both releases. It then renders and validates
the full site before S3 upload. No production files/configuration are touched.
The added pre-upload check validates the new source/rendered maps, all 130
sidebar links, season tabs, availability notes and absence of invented ENSO
labels. Existing map/Snow gates remain enabled.

Final checks should show:

- Existing release: PASS, 44 years, 924 monthly maps, rendered TRUE.
- Earlier release: PASS, 86 years, 1,806 monthly maps, rendered TRUE,
  total_archive_years 130.

Review WY1896, several intervening decades, WY1981 and the WY1982 boundary;
check all season tabs, SPI-12, stable PNG links and navigation into recent
years. Confirm retained daily-detail/Snow sections in later years. Production
promotion remains a separate step after staging acceptance.

Release tooling verification November 19: 171 publication/deployment/legacy
assertions passed, including repeatable earlier-page generation, rejection of
invented ENSO labels, all 130 navigation entries and retained later-year detail.
A two-era end-to-end smoke test exported WY1896 with final footers, staged it
alongside WY2005, rendered both pages and passed map/link/sidebar checks for
both releases. The full 1,806-image publication export and staging run remain
the user-executed steps above.

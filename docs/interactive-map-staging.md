# Interactive Maps staging handoff

This release adds the Interactive Maps page/navigation, 39 Current Conditions
views with Measure controls, seven Daily History views over a retained 30-day
cache, and 28 Monthly Climate choices. It is for staging testing first.

Only the twelve reviewed October 2026 monthly binary payloads, their integrity
receipts, the monthly manifest and geographic boundaries need transferring.
Daily/current data are rebuilt from the VM's own caches. Do not transfer laptop
PRISM/SNODAS PNGs, station pages, the full processed cache or rendered `_site`.
The monthly seed is deliberately a fixed October review snapshot; this release
does not select subsequent monthly releases or automate daily viewer rebuilding.
Repeat the cached staging preparation after a staging data refresh when testing
new dates. Automatic refresh is a follow-up before production promotion.

## Laptop

Commit the viewer modules, scripts, assets, tests, site page/configuration,
deployment validation and related documentation. Leave generated Home/synopsis
edits, unrelated IVT work and stray untracked files out of the commit. Push the
reviewed `codex/daily-explorer` commit and record `git rev-parse HEAD`.

In R, from the project root:

```r
source("scripts/package-interactive-map-staging-seed.R")
```

This creates `data/diagnostics/swc-interactive-monthly-seed.tar.gz` and its
`.sha256` companion using R's Windows-safe internal tar implementation.
Transfer both to `/home/crimmins/incoming/` on the staging VM. The reviewed
archive is approximately 3.6 MiB. Generated data and archives stay out of Git.

## VM

Use `/home/crimmins/RProjects/SWClimateWatch-staging`. Source
`/home/crimmins/.config/swclimatewatch/staging.env` with exported variables;
verify the destination is exactly
`s3://cales-climate-reports/climate/watch-staging/` and the state directory is
`/home/crimmins/.local/state/swclimatewatch-staging`.

Hold that state directory's `daily.lock` for checkout, seed installation,
preparation and publication. Save generated tracked site content in a named
stash, require the remaining tracked tree to be clean, fetch and detach at the
exact recorded laptop commit. Leave production's checkout/environment alone.

Verify the transfer with `sha256sum -c` in `/home/crimmins/incoming`, then extract
the archive into `data/processed/interactive-map-monthly-seed`. Rebuild the map
catalog/status before preparing the viewer, to bind Current Conditions to the
VM's verified images and exact numerical dates:

```bash
Rscript scripts/build-map-product-site.R
Rscript scripts/stage-cached-interactive-map-site.R
Rscript -e 'source("R/interactive-map-site.R"); validate_interactive_map_site()'
Rscript scripts/publish-site-s3.R
Rscript scripts/check-interactive-map-publication.R
```

Preparation verifies every payload against its source values/missing mask and
reports missing daily inputs or unavailable Current Conditions products without
substituting older dates. No climate downloads occur in these viewer steps.
Normal publication still renders/validates all other products. Viewer source
checks occur before rendering and source/rendered checksum checks occur before
any S3 upload. Controls and styles have content-versioned URLs.

## Browser checks

Open the staging Interactive Maps page and its full-screen link. Check all three
views, matching period/date labels, variable/measure/metric filtering, daily date
arrows, representative point values, dry-spell percentile direction, freeze
count/anomaly pairing, rainfall units and the three water-year extreme stats.
Test Terrain/Satellite with roads/place labels and None without hosted tiles.
Check a narrow screen, repeat switches and reloads. Monthly should still show
October 2026; Current Conditions and Daily History should show their own VM
cache dates. Complete phone/performance acceptance before production promotion.

# Interactive Maps staging handoff

This release adds the Interactive Maps page/navigation, 39 Current Conditions
views with Measure controls, seven Daily History views over a retained 30-day
cache, and 28 Monthly Climate choices. It is for staging testing first.

Automatic refresh uses the VM's monthly product grids, daily grids, Current Maps
status and reference caches. No new data transfer is required after the original
staging trial. Do not transfer laptop
PRISM/SNODAS PNGs, station pages, the full processed cache or rendered `_site`.
The first staging trial used a fixed October seed; the automatic workflow no
longer uses it. Monthly selection follows the accepted Monthly Climate page,
not the system calendar or an unaccepted partially built month. Its numerical
markers and PNG hashes must agree with that release. A matching verified viewer
cache may be retained after an incomplete refresh; without one publication stops.
Monthly downloads/revisions still follow the existing monthly updater's window
and request limits. The viewer makes no upstream requests. No new cron job or
environment toggle is needed when the Interactive Maps page is present.

## Laptop

Commit the viewer modules, scripts, assets, tests, site page/configuration,
deployment validation and related documentation. Leave generated Home/synopsis
edits, unrelated IVT work and stray untracked files out of the commit. Push the
reviewed `codex/daily-explorer` commit and record `git rev-parse HEAD`.

The original seed packaging commands remain available for standalone snapshots.
They are unnecessary for automatic daily workflow testing. For local review:

```r
source("scripts/build-interactive-map-site-preview.R")
options(swc.interactive.full_site=FALSE)
source("scripts/preview-interactive-map-site.R")
```

This uses the same accepted-release refresh path as publication, with no uploads.

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

To test preparation alone after checkout, rebuild the map catalog/status before
preparing the viewer, to bind Current Conditions to the VM's verified images and
exact numerical dates:

```bash
Rscript scripts/build-map-product-site.R
Rscript scripts/stage-cached-prism-monthly-site.R
Rscript scripts/stage-cached-interactive-map-site.R
Rscript -e 'source("R/interactive-map-site.R"); validate_interactive_map_site()'
Rscript scripts/publish-site-s3.R
Rscript scripts/check-interactive-map-publication.R
```

Preparation verifies every payload against its source values/missing mask and
reports missing daily inputs or unavailable Current Conditions products without
substituting older dates. No climate downloads occur in these viewer steps.
The daily runner prepares the viewer after the monthly step and before deciding
whether the site is unchanged. A recovered grid or changed reference therefore
triggers reconsideration. Site-only publication also refreshes the viewer before
rendering. The input signature and complete source asset checks reuse unchanged
preparation, including the second call during publication. Invalid output assets
are rebuilt. The default retention is 30 days; missing cells/dates retain their
explicit unavailable behavior without substitution or zero filling.

The run log includes an Interactive Maps summary. Details are in
`data/diagnostics/interactive-map-pilot/workflow-status.csv`; monthly numerical
release caches are in `data/processed/interactive-map-monthly-releases/`.
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
the same ending month as Monthly Climate; Current Conditions and Daily History should show their own VM
cache dates. Complete phone/performance acceptance before production promotion.

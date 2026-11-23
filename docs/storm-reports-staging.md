# Storm report staging trial

November 22: this manual trial passed staging review. For the new daily workflow
and its persistent `SWC_STORM_REPORTS` flag, use [daily integration](storm-reports-daily.md).
The instructions below describe the earlier snapshot-only trial.

Manual, staging-only trial after the local report/timeline review. Automatic
daily report refresh and production publication are not enabled. The only opt-in
is `SWC_STORM_REPORTS_STAGING=true`, set inside the supplied trial process, with
both exact staging destination and staging state-directory guards.

## Laptop checks and files

```r
source("scripts/build-daily-explorer-storm-reports-pilot.R")
source("scripts/test-storm-reports-pilot.R")
source("scripts/test-storm-reports-staging.R")
```

Commit the storm report R modules, scripts/assets, tests and documentation,
plus the guarded additions to `scripts/stage-daily-explorer.R` and
`scripts/publish-site-s3.R`. Do not add unrelated IVT experiments, generated
pages, downloaded caches or stray command-text files.

**No cache, map, or publication bundle transfer is needed.** The VM reuses its
own verified Explorer PNGs, circulation manifests and weather means. The report
adapter overlays only report JSON, the small catalog and browser assets. It
requests AZ/NM report metadata for the VM's retained Explorer dates in bounded
chunks of at most 62 UTC dates, plus the preceding UTC date needed for PRISM
alignment. The trial is bounded to 400 Explorer dates. Cached chunks are reused
on reruns; recent-data refresh/revisions belong to the later daily integration.

Local raw report RDS files remain under `data/raw/storm-reports/az-nm`; they are
not uploaded to the website. The laptop's old sample range is not substituted
for the VM's current date coverage.

## VM

Acquire the staging lock, preserve generated tracked pages in a stash, require
a clean tracked checkout, fetch the reviewed branch and detach at its new HEAD.
Compare that hash to the laptop's pushed commit. Leave unrelated untracked
generated product pages alone. Do not apply the generated-page stash over the
new release.

Then run:

```bash
bash -n scripts/test-storm-reports-staging.sh
bash scripts/test-storm-reports-staging.sh
```

The script loads only staging.env, locks the staging workflow and logs to
`/home/crimmins/.local/state/swclimatewatch-staging/logs/storm-reports-staging-*.log`.
Normal site-only publication builds the normal Daily Explorer first, including
its weather maps/means. The staging overlay then preserves that data payload and
adds `storm_reports_enabled=true`. Assets receive the existing content-hashed
filenames and cache policy. A separate diagnostic candidate is validated before
overlaying the staged source. Source and rendered storm checks run inside
publication **before S3 upload**, then again at the end of the trial.

Validation verifies per-day file checksums, schemas/dates/identifiers, counts,
PRISM/UTC timeline summaries for all three regions, availability flags, control
markup and linked versioned browser assets. The isolated laptop test additionally
proves production is rejected, original weather data/assets remain unchanged,
and corrupted report files fail validation.

## Browser acceptance

Review <https://cales.arizona.edu/climate/watch-staging/daily-explorer/>:

- Date buttons, bar selection, season/year and AZ/NM selection stay linked.
- Report timing defaults to Match precipitation map; UTC and trailing 7/30-day
  ranges show correct bounds and explicit missing coverage.
- Daily bar counts equal the one-day report view for that region/timing. The
  strip stays daily/all-types when report type/search or trailing windows change.
- Rain amounts and distinct flood/flash-flood markers, previews, pinned selection,
  clear selection, coincident report chooser, table pages and bulletin links work.
- Reports in view updates counts and rainfall/hail/wind-gust maxima when panning,
  zooming or changing filters. Clicking a maximum pins the corresponding report.
  Type counts apply the shared type filter; All types clears only that filter.
  Fit map to matching reports changes extent while retaining filters. Missing
  coordinates, unavailable magnitudes/units, partial coverage and ties are explicit.
  The panel is beside the map on desktop and below it on narrow screens.
- Existing daily/7-/30-day weather maps still work, including unavailable states.
- The phone layout remains contained, with report table scrolling internally.

The next ordinary staging rebuild can restore the standard Explorer until daily
integration is explicitly added. Repeat this trial script to restage this report
snapshot. Do not add the trial flag permanently to production.env or staging.env.

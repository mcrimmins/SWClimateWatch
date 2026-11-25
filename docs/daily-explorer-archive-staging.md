# July archive staging trial

Prepared November 24, 2026, after accepted local full-July/navigation review.
No production promotion or cleanup is included. This trial preserves the
normal current Daily Explorer and publishes the fixed reviewed archive at:

`https://cales.arizona.edu/climate/watch-staging/daily-explorer/archive-pilot/`

## Acceptance recorded November 24

The full staging daily run exited 0 after 2,781 seconds (46m 21s), ending
12:02:37 America/Phoenix. The pre-run archive release checksum matched after
the run, and source/rendered archive checks passed: four month routes/36
dates, with July's 31 dates, 217 PRISM maps, 93 daily weather maps, 186 mean
maps, 360 reports and 856 hazards. All referenced archive files survived the
daily workflow unchanged; current Explorer paths remained separate.

This confirms July trial publication/retention. The 46m 21s duration covers
the entire daily workflow and cannot be treated as archive overhead. Production
and permanent environment files were not changed. Seasonal checks and a
bounded full-year plan precede expanding/promoting the historical archive;
cleanup remains deferred until production archive acceptance.

## Bundle

Run `source("scripts/export-daily-explorer-archive-staging.R")` on the laptop.
It validates the integrated release and creates:

- `data/diagnostics/swc-daily-explorer-archive-pilot.tar.gz`
- `data/diagnostics/swc-daily-explorer-archive-pilot.tar.gz.sha256`

Only manifest-listed publication files are included, with an exact tar-entry
list check. The checksum sidecar uses Linux-compatible SHA256 formatting.
Transfer both to `/home/crimmins/incoming/` and verify with `sha256sum -c` there.
Extract under the staging checkout's
`data/diagnostics/daily-explorer-archive-integrated/` while holding its daily
lock. Source GRIBs, decoded caches and pilot work directories are unnecessary.
The VM performs no historical rendering/downloads to publish this bundle.

## Staging publication and retention

Check out the committed source in the staging checkout. Preserve generated
tracked pages before checkout and stop if other tracked changes remain.
Compare the resulting commit with the laptop. After importing the bundle:

```bash
bash -n scripts/test-daily-explorer-archive-staging.sh && bash scripts/test-daily-explorer-archive-staging.sh publish
```

The script guards the exact staging destination/state, takes its daily lock,
loads staging.env and enables process-only report/hazard/archive flags. Normal
site rendering and publication run; archive source/rendered checks are required
centrally before S3 upload. It copies the bundle into
`site/daily-explorer/archive-pilot/`, preserving unchanged bytes/mtime and
leaving ordinary current Explorer files under their normal ownership.
The existing Quarto `daily-explorer/**` resource rule includes the trial.
Permanent environment files and production are not changed.

Review the URL above, including July maps/means, both timeline rows, events,
saved selections, and switching to PRISM-only samples. Then run:

```bash
bash scripts/test-daily-explorer-archive-staging.sh daily
```

This first validates the existing source/rendered trial, records its immutable
release digest and invokes the standard VM preflight/full daily runner with a
temporary staging-only configuration. The runner owns its normal daily lock.
Afterward, a fresh archive staging report must exist, the saved release digest
must match, and every source/rendered referenced file must still validate.
A skipped job/publication produces an explicit stop rather than acceptance.
This checks retention across a real current-data refresh/render/upload, not
merely another archive copy. Inspect the printed timestamped logs and confirm
normal current Explorer coverage as well as the fixed July trial afterward.

The archive folder can remain in staging source between trial runs. Future
archive ownership/rollover/daily integration and production promotion require
separate acceptance; this does not backfill more years or alter the normal
current Explorer navigation. The transferred bundle is immutable historical
content, so its sample current dates remain those reviewed on the laptop.

## Local checks

`source("scripts/test-daily-explorer-archive-staging.R")` uses diagnostic
copies only. It checks production/explicit-destination rejection, stages the
reviewed archive, runs the real current-map adapter with two then one real
sample dates, verifies that obsolete current maps were pruned while every
archive file stayed identical, and validates a separate rendered-layout copy.
The VM publication run supplies the actual Quarto rendered-output check.
No local test uploads anything. Rehearsal copies and transfer bundles are
included in the later cleanup inventory, not deleted during this trial.

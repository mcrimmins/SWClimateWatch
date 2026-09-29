# SNODAS daily update and current maps

This is a separate October 1-May 31 update path for the Arizona-New Mexico
padded footprint, with a June 1-14 closeout to catch late May postings. It
does not change the PRISM update. On its own, it stages **current observed
SWE and departure maps** on a dedicated Quarto page after a quality check,
but does not render the site, upload to S3, or schedule itself. The unified
daily entry point can run both updates and publish them. The WY2005-WY2025
historical reference remains fixed; new years are observations, not additions
to that reference.

## What one run does

1. Outside October-May and the June 1-14 closeout, stop without a network
   request or file change. The June closeout checks only dates through May 31.
2. During the cool season, check the current monthly SNODAS directory for
   archives actually listed by NSIDC. Use at most one additional directory
   request to catch up an unchecked month or recheck a month last seen before
   its end. Listings are cached under
   `data/diagnostics/snodas-update/monthly-directory-inventory.csv`.
3. Plan only listed dates from October 1 through today. Already verified
   regional SWE/depth pairs remain complete even if their source tar has
   been removed.
4. Process up to five dates per run, prioritizing previously downloaded
   archives after an interrupted run. Download at most five new archives
   with the existing paced SNODAS downloader. The two-variable regional
   files are written in inches.
5. By default, verify each regional pair against its source archive and
   release the large full-domain tar. If processing or verification fails,
   the tar is retained for inspection and the next run can resume.
6. Select the latest verified processed date in the current season. If its
   observed SWE and centered-five-day-median departure pass the map-quality
   gate, stage two categorical PNGs and update `site/pages/current-snow.qmd`.
   An unchanged run skips the map build. A `REVIEW` or `FAIL` map stays in
   local diagnostics and never replaces the last published date. At the start
   of a new water year, the page shows a waiting message until a map passes.

The directory request limit (two) and new-archive request limit (five) are
separate. No speculative requests are made for dates missing from the
directory listing. A newly posted day can therefore be behind today's
calendar date. A run with no new listing is normal.

The updater does **not** yet revisit already processed days to detect later
remote revisions or run the full season quality audit. In particular, the
inventory tells us which archives exist but not whether an existing archive's
contents changed. The existing [map quality gate](snodas-map-pilot.md) checks
coverage, reference overlap, screened cells, and very high modeled SWE before
site staging. A quality hold needs review; it is not an automatic mask or an
approval to publish.

**October 1, 2026 readiness:** The season switch starts WY2027 on October 1.
`scripts/update-snodas.R` checks for *listed* current-season archives,
processes up to five dates, and then runs the separate current-map stage.
The unified `scripts/daily-update-and-publish.R` now runs this snow step after
the PRISM step, validates the rendered snow page, and syncs site changes.
Neither script is scheduled to run by itself. An October 1 listing may have no
archive yet; that is normal, and the page remains in its waiting state. The
unified entry point renders and deploys that waiting page or the last
quality-passing map. See [SNODAS remaining work](snodas-next-steps.md) for
unattended-operation hardening and future map ideas.

## RStudio console

From the project root, run the no-network check now:

```r
source("scripts/load-snodas-daily-update.R")
snodas_update_season(Sys.Date())
testthat::test_file("tests/testthat/test-snodas-daily-update.R")
```

From June 15 through September, `snodas_update_season()` returns `NULL`; sourcing
`scripts/update-snodas.R` then reports a skip and makes no requests. During
October-May, the following command performs one capped live update:

```r
source("scripts/update-snodas.R")
swc_snodas_update_result$summary
swc_snodas_map_result$status
```

Repeat it if `remaining` or `months_pending` is positive. If NSIDC
returns a temporary error, rerun later; completed regional files and
inventory checkpoints are kept. The default `retain_raw = FALSE` keeps
the local footprint lean. Map status is `OUT_OF_SEASON`, `WAITING`, `STAGED`,
`UNCHANGED`, or `HELD`. Inspect the date and quality gate before rendering
and deploying the site; `HELD` means no new public image was staged. To inspect the next run
without downloading,
load the functions, then use the saved inventory:

```r
source("scripts/load-snodas-daily-update.R")
plan <- plan_snodas_daily_update()
preview_snodas_daily_update(plan)
```

That preview uses the last saved listing; it does not check NSIDC and may
lag a newly posted day.

For a no-network October 1 boundary check before the season begins, run:

```r
source("scripts/load-snodas-current-site.R")
snodas_update_season(as.Date("2026-10-01"))
snodas_current_site_page_text(2027L)[1:12]
testthat::test_dir("tests/testthat", filter = "snodas-current-site")
```

The current-snow page is linked in the left navigation. It is a site *source*
page, not a deployment. For a manual snow-only update, render and deploy after
visual inspection. Alternatively, use the unified daily script described in
the [README](../README.md#s3-deployment) for a single manually started PRISM,
SNODAS, render, validation, and sync run. Snow failures do not block a valid
PRISM publication; they remain visible in the daily run log.

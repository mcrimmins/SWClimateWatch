# Standard Explorer and daily Streamflow

Status: local implementation; full staging daily test required before production.

Enable `SWC_STREAMFLOW=true` together with the existing `SWC_DAILY_CONNECTED=true`.
The standard connected Explorer receives the reviewed jump navigation and a
collapsed Streamflow section. Gauge tables remain collapsed. Hydrographs default
to seven days when Map view is Single day. Archived dates outside the retained
90-day USGS window explicitly show unavailable data.

The daily runner refreshes the 32 gauges through yesterday. It rechecks a 14-day
revision overlap, reuses verified primary-series metadata and approved calendar-day
statistics, and makes no historical-statistics requests in the daily loop. Source
requests share a 45-second deadline and a 60-request cap. The VM pilot measured
about 12 seconds for 32 requests. This is a target, not a guaranteed runtime.
Metadata and historical statistics remain the reviewed reference snapshot;
refreshing those references is separate maintenance, not a daily download.

Per-gauge failures retain verified observations with their source status. A global
failure retains the sealed previous release, records PARTIAL and adds an explicit
notice to the widget. No verified release stops publication when first enabling
Streamflow. Subsequent daily runs retry automatically. Site-only rendering reads
the verified release without USGS requests.

Keep `data/raw/streamflow-pilot`, `data/raw/streamflow-statistics`,
`data/diagnostics/streamflow-network-pilot/state` and
`data/diagnostics/streamflow-daily`: these now support operational Streamflow.
The last directory contains candidate reports, a sealed release, a previous
release and `workflow-status.csv`. Do not include these in pilot cleanup.

The connected release seal includes all Streamflow files, the current frame,
both archive years' frames and the navigation shell. Archive data files stay
unchanged. Source and rendered validation runs before S3 publication.

## Test locally

```r
source("scripts/test-streamflow-daily.R")
```

## Test the full staging daily workflow

After checking out the pushed commit in the staging checkout:

```bash
bash -n scripts/test-streamflow-daily-staging.sh &&
bash scripts/test-streamflow-daily-staging.sh
```

This uses the existing VM USGS seed and verified gauge state; no new transfer is
needed. A temporary configuration enables Streamflow for the full daily test.
Permanent environment files and production are unchanged. Inspect the standard
staging Daily Explorer, not `streamflow-trial/`, afterward.

For a navigation-only change after the verified daily release exists, use
`bash scripts/publish-streamflow-navigation-staging.sh`. This holds the staging
lock, tests nested/full-screen navigation and republishes from cached data.
Jump buttons scroll the outer site page through both embedded frames; they also
open collapsed sections and focus their headings. The daily test includes a
regression check for this nested layout, reduced motion and fixed site headers.

```bash
Rscript scripts/check-streamflow-daily.R
cat data/diagnostics/streamflow-daily/workflow-status.csv
cat data/diagnostics/streamflow-daily/candidate/last-run.csv
```

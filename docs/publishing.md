# Updating and publishing the site

Run these commands in the RStudio Console from the **SWClimateWatch project
root**. For the normal daily update and deployment, use this one line:

```r
source("scripts/daily-update-and-publish.R")
```

It checks PRISM for new or revised data, updates the current maps when needed,
checks SNODAS during October-May and the June closeout, then renders, validates,
and syncs changed site content to the live website. The destination is
`s3://cales-climate-reports/climate/watch/` in `us-west-2`. No remote files are
deleted. It is safe to rerun: existing downloads and processed data are reused,
and the site sync is skipped if its source content has not changed since the
last successful daily publication. This is a manual command, not a scheduler.

## Which command should I use?

| Purpose | RStudio Console command | Changes the live site? |
| --- | --- | --- |
| Normal daily update and publish | `source("scripts/daily-update-and-publish.R")` | Yes, if site content changed |
| Preview the entire daily workflow, including the proposed S3 sync | `source("scripts/load-daily-publish.R"); run_swc_daily_publish(dry_run = TRUE, force_publish = TRUE)` | No |
| Update data and republish even when the site fingerprint is unchanged | `source("scripts/load-daily-publish.R"); run_swc_daily_publish(dry_run = FALSE, force_publish = TRUE)` | Yes |
| Publish existing local data/site changes without checking for new PRISM or SNODAS data | `source("scripts/publish-site-s3.R")` | Yes |
| Preview a site-only render and S3 sync | `source("scripts/deploy-site-s3.R"); deploy_swc_site("s3://cales-climate-reports/climate/watch/", dry_run = TRUE)` | No |

**Important:** The full-workflow preview still downloads/checks live data and
may regenerate local maps. `dry_run = TRUE` prevents only the S3 upload. Use the
site-only preview if you do not want a climate-data update. The site-only
commands build the map catalog and render the site from existing maps; they do
**not** regenerate map PNGs after a change to map-drawing code. For that, run
the [local map-only rebuild](../README.md#local-prism-downloader-development)
first, then use the site-only publish command.

The site-only publisher does not update the daily workflow's success marker, so
the next normal daily run may sync the same site again. All commands require
Quarto and a configured AWS CLI with write access to the bucket; credentials
are not stored in this repository. A failed render or validation stops the
sync. The daily workflow also validates the Current Snow page before syncing.

## Checking the result

The normal daily command prints a final status. In the same RStudio session,
you can inspect it with:

```r
swc_daily_publish_result$status
```

`PUBLISHED` means the live sync succeeded; `SKIPPED_UNCHANGED` means no sync
was needed. A full-workflow dry run returns `PREVIEW`. The daily workflow logs
attempts in `data/diagnostics/daily-publish/runs.csv` and writes the last
successful live site fingerprint to
`data/diagnostics/daily-publish/last-success.csv`. These are local diagnostics,
not files uploaded to the website.

The site-only command returns `swc_publish_result` in the RStudio session. It
does not update the climate data or the daily publication log.

## Optional phone notifications with ntfy

Install the ntfy app on your phone and subscribe to a topic. To enable alerts,
set the same topic in your **local R environment**, not in this repository:

```r
Sys.setenv(SWC_NTFY_TOPIC = "YOUR_LONG_RANDOM_TOPIC")
source("scripts/load-daily-publish.R")
swc_ntfy_notify("test", "Southwest Climate Watch test notification")
```

The topic setting lasts for the current R session. For future RStudio sessions,
put `SWC_NTFY_TOPIC=YOUR_LONG_RANDOM_TOPIC` in your user-level `~/.Renviron`
and restart RStudio. The project also ignores a local `.Renviron` file, but
the user-level file keeps this setting out of the project entirely. The
default server is `https://ntfy.sh`. For a different HTTPS ntfy server, set
`SWC_NTFY_SERVER`; if that server requires authentication, also set
`SWC_NTFY_TOKEN` to a publish-capable access token. Do not share or commit the
topic or token.

Live daily runs then send a start notice, PRISM/data-check milestones, a
publishing notice, and a final success or failure notice. A SNODAS failure or
quality hold sends a warning while the last verified snow page remains in
place. The site-only live publishing command sends start, publishing, success,
or failure notices too. Dry runs send **no** phone alerts. Alert messages are
deliberately high-level; consult the local console and daily-publish log for
the underlying error. A failed ntfy delivery warns locally but does not stop
the update or deployment. An abrupt computer shutdown cannot send a final
failure alert.

On `ntfy.sh`, topics are publicly subscribable unless access control is
configured, so choose a long, unguessable topic and avoid putting private
details in notification messages. See the official [ntfy publishing and topic
guidance](https://docs.ntfy.sh/publish/).

For low-level deployment settings such as a different destination or an
explicit deletion preview, use `deploy_swc_site()` in
[`scripts/deploy-site-s3.R`](../scripts/deploy-site-s3.R). Keep `delete = FALSE`
for routine publishing.

# Connected Explorer staging trial

November 25, 2026. Local navigation and loading fixes were accepted. This
trial publishes a static adapter at
<https://cales.arizona.edu/climate/watch-staging/daily-explorer/connected/>.
It joins current staging data and all twelve accepted WY2025 archive months.
The standard current entry and accepted archive files remain intact.

The local R preview uses read-only server mounts. S3 needs static pages instead:
the staging adapter adds base paths to the original publication files and
content-hashed navigation scripts. The monthly context loader uses that base
path for adjacent metadata. No map files are duplicated or rebuilt. The
adapter adds approximately 0.8 MB; no new cache transfer is required when the
accepted WY2025 release remains on the staging VM.

`SWC_DAILY_CONNECTED_STAGING=true` enables construction after cached sources
are prepared and browser assets are versioned. The central deploy function
checks the exact staging bucket/state before work and validates all adapter
hashes, current data/script hashes, archive release seal, catalog cutoff and
source/rendered agreement before upload. This flag is set only inside the
test script, not in permanent environment files. The same script enables the
existing WY2025 staging adapter to retain and validate its accepted release.

## Laptop

In Windows Command Prompt:

```bat
cd /d C:\Users\Crimmins\RProjects\SWClimateWatch
git add --pathspec-from-file=scripts/daily-explorer-connected-release-files.txt
git diff --cached --stat
git diff --cached --check
git commit -m "Add connected Explorer navigation and deferred map loading"
git push origin codex/historic-monthly-pilot
git rev-parse HEAD
```

Review the staged list before committing. Unrelated station documentation,
moisture pilots, generated products and stray command-text files stay out.

## VM

Replace the placeholder with the laptop hash, then run:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  expected_commit=PASTE_LAPTOP_COMMIT_HASH_HERE
  test "${#expected_commit}" -eq 40
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
  git fetch origin codex/historic-monthly-pilot
  test "$(git rev-parse FETCH_HEAD)" = "$expected_commit"
  git stash push -m "Staging generated pages before connected Explorer" -- \
    site/index.qmd site/_quarto.yml site/pages/_synopsis-content.qmd \
    site/pages/current-snow.qmd site/pages/snow-conditions.qmd \
    site/pages/monthly-climate.qmd site/pages/archive
  git status --short
  test -z "$(git status --porcelain --untracked-files=no)"
  git switch --detach "$expected_commit"
  test "$(git rev-parse HEAD)" = "$expected_commit"
  test -f scripts/test-daily-explorer-connected-staging.sh
  git rev-parse HEAD
)
```

Continue only if that block completes successfully with the laptop hash:

```bash
bash -n scripts/test-daily-explorer-connected-staging.sh &&
bash scripts/test-daily-explorer-connected-staging.sh
```

The script locks staging, runs adapter tests, performs a cached site-only
publication and validates the source/rendered connected release. It prints
its timestamped log path under the staging state directory. It requires the
previously imported `data/diagnostics/daily-explorer-wy2025-release/` bundle.
No observation or map backfill is scheduled by this step.

## Review

Open the connected trial URL explicitly. Test current → January → July →
current; January with 30-day comparison and weather open; reload saved links;
previous/next across month edges; report/hazard counts and panels; narrower
screens and scrolling through deferred thumbnails. Dates in a gap remain
unavailable. The VM trial should use its current data rather than the laptop's
older diagnostic cache.

Local static browser QA confirmed January 31 with 30-day comparison, loaded
PRISM/weather maps, report/hazard metadata and 60 deferred comparison images
at the top of the page, followed by return to the local current date. R tests
cover staging guards, sealed asset routing and changed-file rejection; the
JavaScript tests cover date stability, one-pass restoration and viewport loads.
Staging acceptance, full daily-run retention and replacement of the standard
entry remain subsequent steps before production promotion.

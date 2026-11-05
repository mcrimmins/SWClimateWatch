# Template synopsis: staging release

The release adds Home Maps/Synopsis tabs (Maps first/default) and the directly
linkable `pages/synopsis.html`. AI is excluded from publication. Review
candidates remain local/diagnostic only. Regional snow narrative is pending;
the synopsis links to Current Snow without inferring regional snow conditions.

## Laptop: commit and push

Run in the SWClimateWatch terminal. The synopsis patterns include the deferred
local AI experiments as reference; none are called by the publishing path.
Unrelated IVT files and the accidental filename are deliberately excluded.

```bat
cd C:\Users\Crimmins\RProjects\SWClimateWatch
git add R/conditions-synopsis-*.R R/map-product-site.R config/conditions-synopsis.yml
git add scripts/*conditions-synopsis*.R scripts/deploy-site-s3.R
git add tests/testthat/test-conditions-synopsis-*.R
git add site/index.qmd site/pages/synopsis.qmd site/pages/_synopsis-content.qmd
git add docs/development-roadmap.md docs/conditions-synopsis-scope.md docs/synopsis-staging.md
git diff --cached --stat
git commit -m "Add template synopsis to Home tabs and publication workflow"
git push origin codex/daily-explorer
git rev-parse HEAD
```

## VM: check out the staging release

Run after any existing staging job finishes. These commands touch only the
staging checkout/configuration; they do not promote production.

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  mkdir -p /home/crimmins/.local/state/swclimatewatch-staging
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9 || { echo "A staging job is running; wait for it to finish."; exit 1; }

  generated=(site/index.qmd site/pages/current-snow.qmd)
  if git ls-files --error-unmatch site/pages/_synopsis-content.qmd >/dev/null 2>&1; then
    generated+=(site/pages/_synopsis-content.qmd)
  fi
  git stash push -m "Staging generated pages before template synopsis release" -- "${generated[@]}"
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/daily-explorer
  git checkout --detach origin/codex/daily-explorer
  git rev-parse HEAD
)
```

Compare that commit with the laptop's hash. Stop if it differs. Then check and
run the staging workflow with its existing configuration:

```bash
SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env \
  bash scripts/run-production-daily.sh --check

SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env \
  bash scripts/run-production-daily.sh
```

The runner acquires the staging lock itself. Do not hold it manually while
starting the runner. The existing production cron and destination stay unchanged.
Confirm `staging.env` still has
`SWC_S3_DESTINATION=s3://cales-climate-reports/climate/watch-staging/` and
`SWC_PRODUCTION_STATE_DIR=/home/crimmins/.local/state/swclimatewatch-staging`
before running it.
The full run updates inputs, stages the template, renders/validates and syncs
to the configured `watch-staging/` destination. Verify the printed destination
is that staging prefix before letting an upload proceed.

## Review

- Open `https://cales.arizona.edu/climate/watch-staging/` and hard-refresh.
- Maps should be selected initially; switching to Synopsis should preserve
  the dashboard and show the three narrative periods with supporting links.
- Open the standalone page at
  `https://cales.arizona.edu/climate/watch-staging/pages/synopsis.html`.
- Check dates, AZ/NM contrasts, mobile tabs, conditional formatting and links.
- No review-candidate panel or AI introduction should appear.
- A first publication has no prior successful-publication comparison. A later
  successful update enables compatible comparisons; previews/failed syncs do not.
- Inspect any `Template synopsis: WAITING` message and its destination-specific
  diagnostics under `data/diagnostics/conditions-synopsis/publication/` before
  approving the feature. The rest of the site can publish with an explicit
  synopsis waiting notice.

Optional cached site-only publication, when the latest staging maps and station
assets are already correct (also stages/validates the synopsis):

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  set -a
  source /home/crimmins/.config/swclimatewatch/staging.env
  set +a
  test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
  test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
  exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
  flock -n 9 || { echo "A staging job is running; wait for it to finish."; exit 1; }
  TZ=America/Phoenix Rscript scripts/publish-site-s3.R
)
```

Promotion follows review of the exact staged commit. Do not copy the staging
synopsis success marker into production: the two histories intentionally remain
separate. Production starts with its own successful-publication baseline.

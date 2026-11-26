# Combined Explorer production promotion

The user accepted the combined staging viewer and full daily-run retention
of both archive years. The prior trial adapter rejects production by design.
The operational adapter uses `SWC_DAILY_CONNECTED=true`, requires a matching
watch/watch-staging destination and state, and rejects simultaneous archive
trial flags. It stages verified imported WY2025/WY2026 publication files,
builds connected navigation after current weather/events and asset versioning,
and validates both imported/staged/rendered years before upload.

The standard Daily Explorer Quarto page links/embeds the combined viewer.
The original full-screen URL redirects top-level visits to the combined
entry while preserving query/hash selections. Native current assets stay in
place, and the private current frame continues reading them without a redirect.
Both the connected and outer Quarto frames settle resizing updates.

## Laptop

In Windows Command Prompt:

```bat
cd /d C:\Users\Crimmins\RProjects\SWClimateWatch
git add --pathspec-from-file=scripts/daily-explorer-production-release-files.txt
git diff --cached --stat
git diff --cached --check
git commit -m "Enable production combined Explorer and daily archive retention"
git push origin codex/historic-monthly-pilot
git rev-parse HEAD
```

No bundle transfer from the laptop is required; both verified imports are
already on the staging VM. Only the production adapter/entry integration is
new. Run its site-only staging checkpoint before promotion:

## VM staging checkpoint

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9 || { echo "STOP: a staging job is running."; exit 1; }
  git stash push -m "Staging generated pages before operational Explorer" -- site/index.qmd site/_quarto.yml site/pages/_synopsis-content.qmd site/pages/current-snow.qmd site/pages/snow-conditions.qmd site/pages/monthly-climate.qmd site/pages/daily-explorer.qmd site/pages/archive
  git status --short
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/historic-monthly-pilot
  git switch --detach FETCH_HEAD
  git rev-parse HEAD
)
```

Verify that the hash matches the laptop, then:

```bash
bash -n scripts/publish-connected-explorer-staging.sh &&
bash scripts/publish-connected-explorer-staging.sh
```

Review <https://cales.arizona.edu/climate/watch-staging/pages/daily-explorer.html>
and the full-screen link. This uses the production-compatible adapter on
staging without changing staging.env. Code tests, both archives, current
cutoff, static release and page links must pass before upload.

## VM production

After that check passes, run the tested staging checkout's promotion script:

```bash
bash -n /home/crimmins/RProjects/SWClimateWatch-staging/scripts/promote-connected-explorer-production.sh &&
bash /home/crimmins/RProjects/SWClimateWatch-staging/scripts/promote-connected-explorer-production.sh
```

The script locks staging and production, checks that the operational staging
release records the same commit and imported archive seals, preserves generated
production pages in a stash, records the previous production commit, and
checks out the exact staging commit. It copies only both imported publication
releases to production, backs up production.env and persists
`SWC_DAILY_CONNECTED=true` so the existing daily cron uses the adapter.
It then performs a site-only publication with full archive/page validation.
It prints a promotion log path and ends with the production PASS message.
It does not copy raw caches or schedule a historical rebuild.

Review <https://cales.arizona.edu/climate/watch/pages/daily-explorer.html>,
both archive years and Current. Verify the next normal cron log and standard
publication checks. Promotion is pending until the user reports success.

## Hazard index seal correction

The first production attempt stopped before upload because the new full-screen
redirect was inserted after hazards sealed the current Explorer index. The
redirect now runs in cached staging after reports and before the hazard overlay
is assembled/frozen. The late connected adapter does not modify the current
index. Integrity checks are unchanged. Regression fixtures verify the ordering
and that late staging preserves sealed bytes. The final site-only staging
checkpoint now explicitly enables reports/hazards to match production.

For the already-promoted checkout/config/imports, commit the paths listed in
`scripts/daily-explorer-hazard-seal-fix-files.txt`, update the production code
under its daily lock, and run:

```bash
bash -n scripts/retry-connected-explorer-production.sh &&
bash scripts/retry-connected-explorer-production.sh
```

The retry uses the existing imported bundles and performs a site-only build
with reports and hazards enabled, full archive validation and the unchanged
hazard seal check. No historical weather/PRISM rebuild, transfer, or manual
manifest edit is required. Its timestamped log is printed. The existing daily
cron flag remains enabled after the successful retry.

The subsequent attempt exposed that the hazard/report assembler regenerates
the outer HTML, discarding a redirect applied to its input. The final hook
now applies the redirect to the assembled hazard output immediately before
cache versioning and manifest sealing. A regression runs the actual snapshot
assembly function with a regenerating fixture builder, checks every sealed
file hash/size in both work and copied output, and requires the redirect.
The late connected adapter still leaves the sealed current index untouched.

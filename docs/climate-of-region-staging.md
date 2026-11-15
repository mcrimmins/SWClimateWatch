# Climate of the Region: staging release

November 15, 2026. Deploy the reviewed 39-map reference suite and topic-based
layout to watch-staging first. Production stays unchanged until promotion.

## What transfers

The prepared archive contains only
`data/processed/regional-climate-reference/1991-2020/`: 39 approved PNGs,
the map manifest, six source/method CSVs and a portable checksum release record.
No raw inputs, numeric GeoTIFFs, daily year caches or other current/historical
site images need transferring. The fixed 1991–2020 reference is prepared once
on the laptop. Later daily/site-only publication stages and verifies this
cache without requests or climatology calculations. A missing or changed
release stops publication before S3 sync.

## 1. Laptop RStudio

```r
source("scripts/prepare-climate-of-region-transfer.R")
```

This verifies the original reference caches/source inventories and writes:

- `data/diagnostics/regional-climate-transfer/swc-regional-climate-seed.tar.gz`
- the matching `.tar.gz.sha256` file

It uses R's internal tar and relative paths, avoiding the earlier Windows
C:-drive tar error. No S3 upload occurs.

## 2. Laptop Windows terminal (CMD)

```bat
cd /d C:\Users\Crimmins\RProjects\SWClimateWatch

git add .gitignore .gitattributes R/regional-*.R R/map-hotlinks.R

git add "scripts/*regional*" "scripts/*climate-of-region*" scripts/climate-reference-assets/ scripts/deploy-site-s3.R

git add "docs/*regional*" "docs/*climate-of-region*" docs/development-roadmap.md docs/map-hotlinks.md

git add site/_quarto.yml site/styles.css site/pages/climate-of-region.qmd

git add "tests/testthat/test-regional-*.R" tests/climate-reference-controls.cjs

git diff --cached --stat
git commit -m "Add Climate of the Region reference maps and publication checks"
git push origin codex/daily-explorer
git rev-parse HEAD
```

Review the staged list before committing. Do not add unrelated IVT experiments,
stray filenames, data caches, rendered output or generated synopsis changes.
The existing deploy/hotlink test files are unchanged; the new regional release
suite tests both integrations. If other files were already staged, review them
separately rather than assuming they belong to this release.

Transfer using the working VPN/private-IP SSH route:

```bat
ssh crimmins@10.222.142.128 "mkdir -p /home/crimmins/incoming"
scp data\diagnostics\regional-climate-transfer\swc-regional-climate-seed.tar.gz data\diagnostics\regional-climate-transfer\swc-regional-climate-seed.tar.gz.sha256 crimmins@10.222.142.128:/home/crimmins/incoming/
```

## 3. VM staging checkout

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  mkdir -p /home/crimmins/.local/state/swclimatewatch-staging
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9 || { echo 'STOP: a staging job is running.'; exit 1; }
  git stash push -m "Staging generated pages before regional climate release" -- site
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/daily-explorer
  git checkout --detach FETCH_HEAD
  git rev-parse HEAD
)
```

Compare the printed hash with the laptop hash. It must be the same commit.
If the clean-tree check fails, inspect remaining tracked changes before proceeding.

## 4. VM install, verify and publish to staging

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
bash scripts/test-climate-of-region-staging.sh
```

The helper checks the staging destination, project/state paths and lock,
verifies SHA256 and archive paths, installs the release cache, verifies all
39 maps and records, stages the page, renders/validates the full existing site
and uploads only to watch-staging. It performs no climate downloads or map
recalculation. Existing PRISM/SNODAS/station/weather checks remain active.
It takes the staging lock for the whole install/build/publish step.

For publication reruns after the bundle is installed, use the normal staging
site-only publisher under the staging configuration/lock; unpacking again is
unnecessary. The normal daily workflow now restages/checks the reference release
as well. The VM does not run the laptop pilot builders.

## 5. Review

- [Climate of the Region](https://cales.arizona.edu/climate/watch-staging/pages/climate-of-region.html)
- [Map catalog](https://cales.arizona.edu/climate/watch-staging/maps/catalog.html)
- [Annual precipitation hotlink](https://cales.arizona.edu/climate/watch-staging/maps/latest/climate-region/annual-precipitation.png)
- [Summer share hotlink](https://cales.arizona.edu/climate/watch-staging/maps/latest/climate-region/summer-precipitation-share.png)

Expected reference validation: `PASS`, 39 maps, 3 tabs, 0 failed, rendered TRUE.
The report is `data/diagnostics/regional-climate-site-check/summary.csv`.
All 39 maps enter the stable-link catalog under Climate of the Region, using
`maps/latest/climate-region/<filename>.png`. These are fixed-reference maps,
not current-condition dates. Existing page/JS/CSS/JSON revalidation and stable
image cache policies apply unchanged.

Check selected/all-metric views, remembered periods, Annual total fallback,
seasonal share preference, comparison metrics, mobile wrapping, download links,
collapsed explanations and sidebar placement above About. Review staging before
production promotion. Production will need the same small release directory
copied from staging when promoting this commit.

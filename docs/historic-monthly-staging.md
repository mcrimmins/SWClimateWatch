# Monthly Historic Years staging release

Scope: 44 existing WY1982–2025 pages, 924 monthly maps; retain 176 daily-detail
and 84 historical Snow maps. No backfill before WY1982. Production remains on
its currently pinned commit until staging review and a separate promotion.

The completed local numeric and rendered checks passed. Export a separate
portable release rather than copying the local review website or absolute-path
RDS checkpoints. The export reads verified cached TIFFs, re-renders the maps
with final publication footers, and resumes from per-map checkpoints. No data
downloads, SPI refits or site changes are made. Allow a substantial graphics
pass the first time (924 maps); reruns reuse matching output images.

In laptop R/RStudio, from the project root:

```r
source("scripts/export-historic-monthly-release.R")
```

Wait for `Portable archive READY` before packaging. The transferred folder is
`data/processed/historic-monthly-release`: 924 PNGs plus a relative-path manifest
and release seal. Numeric reference matrices, raw monthly grids, existing daily
and Snow caches, and the separate `_site` review folder are not needed on the
VM for this cached publication. Expect roughly 0.7 GiB of images, plus staging
source/rendered copies; check actual archive size after packaging.

Commit only the Historic Years R modules/scripts/assets/tests and the supporting
deployment, validation, map-link catalog, resource and roadmap changes. Leave
unrelated weather/IVT experiments, generated product pages, pasted terminal
files and generated Home content out of the commit. Push
`codex/historic-monthly-pilot` and record its full commit hash.

In Windows Command Prompt, use a relative archive filename (avoids GNU tar
interpreting a Windows drive letter as a remote host):

```bat
tar -czf swc-historic-monthly-release.tar.gz --exclude=*.rds --exclude=export.lock -C data/processed historic-monthly-release
certutil -hashfile swc-historic-monthly-release.tar.gz SHA256
scp swc-historic-monthly-release.tar.gz crimmins@10.222.142.128:/home/crimmins/incoming/
```

On the VM, compare `sha256sum` with the laptop digest, then check out the pushed
feature commit under the staging daily lock. Stash generated `site` changes
first and stop if any tracked modifications remain. Use the explicit feature
ref, not `main`, for this staging test. Record `git rev-parse HEAD` and compare
it to the laptop hash before proceeding.

The checked-in helper loads **only staging.env**, checks both staging
destination and state directory, holds the staging lock, unpacks the release,
stages all pages preserving each VM Snow section, validates source coverage and
checksums, and runs the standard site-only render/validate/upload workflow:

```bash
bash scripts/test-historic-monthly-staging.sh /home/crimmins/incoming/swc-historic-monthly-release.tar.gz
```

The normal site publisher reconciles the new archive only when the local
portable-release folder is present. The publication gate validates all 924
monthly source/rendered images and links, season tabs and retained image
counts. Existing validation continues to check all 352 legacy files, including
the 176 no longer displayed, and historical Snow retains its own publication
gate. Explicit Quarto resources keep superseded legacy URLs available. New
monthly images have stable year/season paths and appear in Map links.

Expected final archive check: `PASS`, `44` years, `924` monthly maps,
`rendered=TRUE`. Inspect WY1982, WY2002, WY2005 and WY2025, all four season tabs,
SPI-12, daily-detail/Snow disclosures and full-resolution PNG links. Production
promotion and any future monthly archive revisions are separate decisions.

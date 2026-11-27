# Map cleanup recovery preparation

This is a preparation and verification tool. There is no deletion mode or
automatic restore. Stop builds/previews before preparing a bundle.

```r
testthat::test_file("tests/testthat/test-map-cleanup-recovery.R", stop_on_failure = TRUE)
source("scripts/prepare-map-cleanup-recovery.R")
map_cleanup_recovery$summary
View(map_cleanup_recovery$manifest)
shell.exec(normalizePath(map_cleanup_recovery$directory)) # Windows only
verify_map_cleanup_bundle(map_cleanup_recovery$directory, project = ".")
```

Preparation reads the existing audit; it does not repeat the full reference
scan. It requires zero scan issues and exact agreement between the proposed
files and their inventory records. Only dated PNGs directly in the two audited
temperature/precipitation folders (source or rendered) are permitted. Missing,
linked, changed, referenced, duplicate and out-of-scope files are rejected.

The original audit captured size and modification time, not SHA-256. Preparation
checks those values first, then records SHA-256 hashes. A same-size change with
an artificially preserved timestamp before preparation cannot be detected from
the old report. Content-hash protection starts at preparation. Source pages or
references may also have changed since the audit: rerun the audit after any
build/publication before considering a future deletion. External hotlinks remain
unknown. A verified bundle does not establish that maps are safe to remove.

Each preparation creates a unique directory under
`data/diagnostics/map-cleanup-recovery/`, containing:

- `recovery.tar.gz`: originals and project-relative restore manifest.
- `restore-manifest.csv`: file paths, sizes, modification times and SHA-256.
- `bundle.json`: archive/manifest SHA-256, audit checksums and original project.
- `audit-*.csv`: the three audit inputs used in preparation.
- `verification.csv` and `READY.txt`: written only after successful extraction,
  checksum comparison and a final content check against every original.

R's internal archive writer warns about paths longer than 100 bytes. These notes
are saved in `archive-notes.txt` when present; exact extracted paths and hashes
must still pass verification. Unexpected archive warnings stop preparation.

Temporary packing/extraction copies are removed; original project maps are
never removed or overwritten. Partial failed output may remain without READY.
Do not treat such a directory as a verified recovery bundle. Recovery verification
can be repeated on a transferred bundle without `project`; supplying `project`
also confirms originals still match. No files are automatically restored into
the project. For future recovery, extract into a separate directory and verify
before any deliberate replacement. Keep the manifest and bundle metadata beside
the archive when transferring it.

PNG compression provides limited savings. Preparation temporarily needs space
for two uncompressed copies plus the archive. A retained bundle on the same disk
does not reclaim the original space. Recovery directories are excluded from
subsequent map reference audits so backup manifests do not keep obsolete maps
alive as publication references. No daily workflow or VM configuration changes.

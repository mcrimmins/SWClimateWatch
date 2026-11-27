# Map cleanup audit

Stop local preview servers and builds, then run from the project root:

```r
source("scripts/audit-map-cleanup.R")
map_cleanup_audit$summary
View(map_cleanup_audit$candidates)
View(map_cleanup_audit$scan_issues)
file.show(file.path(map_cleanup_audit$report_dir, "README.md"))
```

The tool only writes reports under `data/diagnostics/map-cleanup-audit/`.
`inventory.csv` explains every KEEP/HOLD/REVIEW_CANDIDATE decision.
`proposed-cleanup.csv` lists review candidates, `references.csv` records
explicit PNG references, and `scan-issues.csv` records unreadable/skipped text.
Any incomplete reference scan prevents unreferenced files becoming candidates.

Scope is dated PNGs in `site/maps/generated/prism/{temperature,precipitation}`
and their rendered counterparts under `site/_site`. Stable filenames are
always kept. Defaults retain two newest dates per product series and anything
less than 30 days old by either map date or modification date. Recent transfers
may therefore be retained until they age out. Source/rendered copies are listed
separately; their sizes must not be confused with unique published products.

The reference scan includes source/rendered pages, browser scripts, configuration,
documentation and text metadata in processed/diagnostic folders. Matching uses
the complete PNG basename, conservatively retaining collisions and stale references.
Repeated runs exclude the audit's own reports. Text over 25 MiB requiring detailed
inspection is not loaded into R and blocks proposals. This is intentionally a conservative first audit, not a garbage
collector or a guarantee that a file has no consumers. Binary RDS references,
dynamically constructed filenames, external hotlinks, S3 contents and upstream
downloads are not inspected. Nothing is deleted and no deletion/apply mode exists.

If available, ripgrep accelerates the text-reference scan; otherwise the same
checks run in R and can take considerably longer. Large archive folders can also
take a few minutes to enumerate. Progress messages identify both phases. The
audit runs only when explicitly requested; it is not part of daily processing.

Do not remove raw PRISM inputs, imported WY2025/WY2026 releases, historic monthly
releases or stable map URLs based on this report. Retain archive recovery copies
and confirm the next daily production run retains both archive years first.

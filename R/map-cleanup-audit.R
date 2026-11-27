# Read-only inventory. A candidate is a review proposal, never deletion authority.
audit_map_cleanup <- function(project = ".", report_dir = "data/diagnostics/map-cleanup-audit",
    grace_days = 30L, keep_latest = 2L, today = Sys.Date()) {
  stopifnot(length(grace_days) == 1L, is.finite(grace_days), grace_days >= 0,
    length(keep_latest) == 1L, is.finite(keep_latest), keep_latest >= 1)
  project <- normalizePath(project, winslash = "/", mustWork = TRUE)
  if (!dir.exists(file.path(project, "site"))) stop("Project site directory is missing.")
  today <- as.Date(today)
  if (length(today) != 1L || is.na(today)) stop("Invalid audit date.")
  rel <- function(p) substring(p, nchar(project) + 2L)
  within <- function(p) startsWith(tolower(p), paste0(tolower(project), "/"))
  # Only this ignored directory may receive audit output. No site/cache writes.
  if (!grepl("^data/diagnostics/[A-Za-z0-9_/-]+$", report_dir) ||
      any(strsplit(report_dir, "/", fixed = TRUE)[[1L]] %in% c(".", "..")))
    stop("Report directory must be a plain path under data/diagnostics.")
  output <- file.path(project, report_dir)
  # Resolve the nearest existing ancestor to reject links escaping the project.
  ancestor <- output
  while (!file.exists(ancestor)) ancestor <- dirname(ancestor)
  resolved <- normalizePath(ancestor, winslash = "/", mustWork = TRUE)
  if (!within(resolved) && tolower(resolved) != tolower(project)) stop("Report directory resolves outside the project.")
  roots <- c("site", "site/_site")
  groups <- c("temperature", "precipitation")
  rows <- list()
  for (root in roots) for (group in groups) {
    folder <- file.path(project, root, "maps/generated/prism", group)
    files <- list.files(folder, pattern = "[.]png$", full.names = TRUE, recursive = TRUE)
    if (!length(files)) next
    info <- file.info(files)
    rows[[length(rows) + 1L]] <- data.frame(path = rel(files), copy = root, group = group,
      filename = basename(files), bytes = info$size,
      modified = as.character(info$mtime), modified_age_days = as.numeric(difftime(today, as.Date(info$mtime), units = "days")),
      outside_project = !within(normalizePath(files, winslash = "/", mustWork = TRUE)), stringsAsFactors = FALSE)
  }
  empty <- data.frame(path=character(),copy=character(),group=character(),filename=character(),bytes=numeric(),
    modified=character(),modified_age_days=numeric(),outside_project=logical())
  inventory <- if (length(rows)) do.call(rbind, rows) else empty
  n <- nrow(inventory)
  dated <- grepl("-[0-9]{4}-[0-9]{2}-[0-9]{2}[.]png$", inventory$filename)
  dates <- rep(as.Date(NA), n)
  dates[dated] <- suppressWarnings(as.Date(sub(".*-([0-9]{4}-[0-9]{2}-[0-9]{2})[.]png$", "\\1", inventory$filename[dated])))
  inventory$data_date <- as.character(dates)
  series <- sub("-[0-9]{4}-[0-9]{2}-[0-9]{2}[.]png$", "", inventory$filename)
  newest <- rep(FALSE, n)
  for (indices in split(seq_len(n), paste(inventory$copy, inventory$group, series))) {
    valid <- indices[!is.na(dates[indices])]
    if (length(valid)) newest[valid[order(dates[valid], decreasing = TRUE)][seq_len(min(length(valid), keep_latest))]] <- TRUE
  }
  # Text references protect by complete basename, deliberately allowing false
  # positives. This also covers relative/absolute paths, escaped JSON paths,
  # URL-encoded names and source/rendered copies without guessing URL bases.
  extensions <- "[.](qmd|md|html|htm|json|csv|tsv|js|css|ya?ml|xml|txt|R|r)$"
  scan_roots <- file.path(project, c("site", "config", "R", "scripts", "docs", "data/processed", "data/diagnostics"))
  message("Inventory: ", n, " map files. Collecting reference files (large archive folders may take a few minutes)...")
  names_to_find <- unique(inventory$filename)
  hits <- setNames(vector("list", length(names_to_find)), names_to_find)
  issues <- list(); evidence <- list()
  record_issue <- function(p, why) issues[[length(issues) + 1L]] <<- data.frame(path = rel(p), reason = why)
  # rg can discard text with no PNG references much faster than opening every
  # historical JSON payload in R. Fall back to the complete R scan if absent
  # or unsuccessful. Oversize/unreadable files still block proposals.
  rg <- getOption("swc.cleanup.rg", Sys.which("rg"))
  metadata <- NULL
  if (nzchar(rg)) {
    err <- tempfile(); on.exit(unlink(err), add = TRUE)
    args <- c("--files-with-matches", "--text", "--no-ignore", "--hidden", "--fixed-strings",
      "--iglob", shQuote("*.{qmd,md,html,htm,json,csv,tsv,js,css,yaml,yml,xml,txt,r}"),
      "-e", shQuote(".png"), "-e", shQuote("%2Epng"), "-e", shQuote("%2epng"), "--",
      shQuote(scan_roots[dir.exists(scan_roots)]))
    found <- tryCatch(suppressWarnings(system2(rg, args, stdout = TRUE, stderr = err)), error = function(e) NULL)
    code <- attr(found, "status"); if (is.null(code)) code <- 0L
    if (!is.null(found) && code %in% c(0L, 1L) && file.info(err)$size == 0) {
      found <- gsub("\\", "/", found, fixed = TRUE)
      metadata <- unique(found)
      message("Fast reference filter: ", length(metadata), " text files contain PNG references.")
    } else message("Fast filter unavailable; using the complete R reference scan.")
  }
  if (is.null(metadata)) metadata <- unique(unlist(lapply(scan_roots, function(p) list.files(p, pattern = extensions,
    full.names = TRUE, recursive = TRUE, ignore.case = TRUE)), use.names = FALSE))
  # The audit's own reports must never become references on a later run.
  metadata <- metadata[!startsWith(metadata, paste0(output, "/")) &
    !startsWith(metadata,paste0(project,"/data/diagnostics/map-cleanup-recovery/")) &
    !grepl("/(node_modules|[.]git|[.]quarto)/", metadata)]
  message("Checking ", length(metadata), " text files for references...")
  scanned <- 0L
  for (p in metadata) {
    scanned <- scanned + 1L
    if (scanned %% 2000L == 0L) message("Reference scan: ", scanned, "/", length(metadata))
    if (!within(normalizePath(p, winslash = "/", mustWork = TRUE))) {record_issue(p, "Reference file resolves outside project; not read"); next}
    size <- file.info(p)$size
    if (is.na(size) || size > 25 * 1024^2) {record_issue(p, "Reference file exceeds 25 MiB or has unknown size; not read"); next}
    content <- tryCatch(paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), error = function(e) e)
    if (inherits(content, "error")) {record_issue(p, conditionMessage(content)); next}
    # Extract PNG basenames in one pass, avoiding files x maps substring scans.
    tokens <- regmatches(content, gregexpr("[A-Za-z0-9_.%~-]+(?:[.]|%2[eE])png", content, perl = TRUE))[[1L]]
    encoded <- grepl("%", tokens, fixed = TRUE)
    if (any(encoded)) tokens[encoded] <- vapply(tokens[encoded], function(token) {
      # Prose/code can resemble a percent-encoded filename without being a
      # valid URL (including %00). Preserve such tokens verbatim; never let
      # malformed unrelated text abort the read-only reference scan.
      tryCatch(suppressWarnings(utils::URLdecode(token)), error = function(e) token)
    }, character(1))
    matched <- intersect(names_to_find, tokens)
    for (name in matched) hits[[name]] <- unique(c(hits[[name]], rel(p)))
  }
  inventory$reference_count <- vapply(inventory$filename, function(name) length(hits[[name]]), integer(1))
  inventory$reference_example <- vapply(inventory$filename, function(name) paste(head(hits[[name]], 3L), collapse = " | "), character(1))
  inventory$status <- rep("REVIEW_CANDIDATE", n)
  inventory$reason <- rep("Older dated map; no explicit PNG reference found in scanned text", n)
  protect <- function(index, status, reason) {
    inventory$status[index] <<- status; inventory$reason[index] <<- reason
  }
  protect(rep(length(issues) > 0L, n), "HOLD", "Reference scan incomplete; inspect scan-issues.csv")
  protect(newest, "KEEP", "Newest retained map in this product series")
  protect(!is.na(dates) & (as.numeric(today - dates) < grace_days | inventory$modified_age_days < grace_days),
    "KEEP", "Within grace period by map date or file modification date")
  protect(!dated | is.na(dates), "KEEP", "Stable/latest name or unrecognized date; outside dated cleanup scope")
  protect(inventory$reference_count > 0L, "KEEP", "Referenced by page, code, catalog or metadata")
  protect(inventory$outside_project, "HOLD", "File resolves outside project")
  for (name in names(hits)) for (p in hits[[name]]) evidence[[length(evidence) + 1L]] <- data.frame(filename = name, referenced_by = p)
  scan_issues <- if (length(issues)) do.call(rbind, issues) else data.frame(path=character(), reason=character())
  references <- if (length(evidence)) do.call(rbind, evidence) else data.frame(filename=character(), referenced_by=character())
  summary <- if(n) aggregate(bytes ~ copy + status, inventory, sum) else data.frame(copy=character(),status=character(),bytes=numeric())
  summary$gib <- round(summary$bytes / 1024^3, 3)
  candidates <- inventory[inventory$status == "REVIEW_CANDIDATE", , drop = FALSE]
  # Detect concurrent changes to inventoried maps; an unstable snapshot cannot
  # support proposals. Normal runs should be idle during this audit.
  after <- file.info(file.path(project, inventory$path))
  changed <- is.na(after$size) | after$size != inventory$bytes | as.character(after$mtime) != inventory$modified
  if (any(changed)) stop("Maps changed during audit. Rerun while builds are idle; no report written.")
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  write.csv(inventory, file.path(output, "inventory.csv"), row.names = FALSE, na = "")
  write.csv(candidates, file.path(output, "proposed-cleanup.csv"), row.names = FALSE, na = "")
  write.csv(references, file.path(output, "references.csv"), row.names = FALSE)
  write.csv(scan_issues, file.path(output, "scan-issues.csv"), row.names = FALSE)
  write.csv(summary, file.path(output, "summary.csv"), row.names = FALSE)
  writeLines(c("# Map cleanup review (dry run)", "", paste("Audit date:", today),
    paste("Scanned text files:", length(metadata)), paste("Scan issues:", nrow(scan_issues)),
    paste("Grace period:", grace_days, "days; newest maps retained per series:", keep_latest), "",
    "No maps, caches, publication files, S3 objects or Git files were changed.",
    "Only PNGs in PRISM temperature/precipitation folders are inventoried, in source and rendered copies.",
    "Raw/processed caches, archive releases, monthly maps and historical maps are outside scope.",
    "Review candidates are not proven unused: binary RDS metadata, dynamically constructed URLs, external hotlinks and S3 are not audited.",
    "Referenced basenames are protected conservatively even when another directory contains that name.",
    "No deletion commands or apply mode are supplied. Review both copies, references.csv and scan-issues.csv before any separate cleanup.",
    "Run with previews/builds stopped. Keep recovery copies and verify the next production daily run first."), file.path(output, "README.md"))
  print(summary, row.names = FALSE)
  message("Dry run: ", nrow(candidates), " review candidates; ", nrow(scan_issues), " scan issues. Reports: ", output)
  invisible(list(inventory=inventory, candidates=candidates, summary=summary, scan_issues=scan_issues, report_dir=output))
}

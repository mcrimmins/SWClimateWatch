# Preparation/verification only. There is deliberately no delete or restore API.
map_recovery_sha <- function(path) vapply(path, function(p)
  digest::digest(file=p, algo="sha256", serialize=FALSE), character(1), USE.NAMES=FALSE)

map_recovery_paths <- function(project, paths) {
  allowed <- "^site/(_site/)?maps/generated/prism/(temperature|precipitation)/[A-Za-z0-9_.-]+-[0-9]{4}-[0-9]{2}-[0-9]{2}[.]png$"
  if (anyNA(paths) || any(!grepl(allowed, paths)) || anyDuplicated(tolower(paths)))
    stop("Unsafe, duplicate or out-of-scope map path.")
  full <- file.path(project, paths)
  if (!all(file.exists(full)) || any(file.info(full)$isdir)) stop("A proposed map is missing or is a directory.")
  resolved <- normalizePath(full, winslash="/", mustWork=TRUE)
  if (any(tolower(resolved) != tolower(full))) stop("Map path traverses a link or resolves outside its expected location.")
  full
}

verify_map_cleanup_bundle <- function(directory, project=NULL, require_ready=TRUE) {
  directory <- normalizePath(directory,winslash="/",mustWork=TRUE)
  if (require_ready && !file.exists(file.path(directory,"READY.txt"))) stop("Recovery preparation is incomplete: READY marker missing.")
  record <- jsonlite::read_json(file.path(directory,"bundle.json"))
  archive <- file.path(directory,"recovery.tar.gz")
  manifest_file <- file.path(directory,"restore-manifest.csv")
  if (!identical(record$status,"VERIFIED_RECOVERY_ONLY") ||
      !identical(record$archive_sha256,map_recovery_sha(archive)) ||
      !identical(record$manifest_sha256,map_recovery_sha(manifest_file))) stop("Recovery bundle or manifest checksum mismatch.")
  manifest <- read.csv(manifest_file,stringsAsFactors=FALSE)
  required <- c("path","bytes","sha256")
  if (!all(required %in% names(manifest)) || !nrow(manifest) ||
      anyNA(manifest[,required]) || any(!grepl("^[a-f0-9]{64}$",manifest$sha256))) stop("Invalid restore manifest.")
  # Validate names before extracting anything, even for a modified archive.
  allowed <- "^site/(_site/)?maps/generated/prism/(temperature|precipitation)/[A-Za-z0-9_.-]+-[0-9]{4}-[0-9]{2}-[0-9]{2}[.]png$"
  if (any(!grepl(allowed,manifest$path)) || anyDuplicated(tolower(manifest$path))) stop("Unsafe restore manifest paths.")
  expected <- c("restore-manifest.csv",manifest$path)
  entries <- utils::untar(archive,list=TRUE,tar="internal")
  if (anyDuplicated(entries) || !setequal(entries,expected)) stop("Recovery archive entries differ from manifest.")
  scratch <- tempfile("map-recovery-verify-");dir.create(scratch)
  # Only our newly created temporary extraction is removed, never project maps.
  on.exit(unlink(scratch,recursive=TRUE),add=TRUE)
  utils::untar(archive,exdir=scratch,tar="internal")
  extracted <- file.path(scratch,manifest$path)
  if (!all(file.exists(extracted)) || any(file.info(extracted)$isdir) ||
      any(normalizePath(extracted,winslash="/",mustWork=TRUE) != gsub("\\","/",extracted,fixed=TRUE)) ||
      !identical(map_recovery_sha(file.path(scratch,"restore-manifest.csv")),record$manifest_sha256) ||
      !identical(map_recovery_sha(extracted),manifest$sha256) ||
      any(file.info(extracted)$size != manifest$bytes)) stop("Extracted recovery files failed verification.")
  if (!is.null(project)) {
    project <- normalizePath(project,winslash="/",mustWork=TRUE)
    originals <- map_recovery_paths(project,manifest$path)
    if (any(file.info(originals)$size != manifest$bytes) ||
        !identical(map_recovery_sha(originals),manifest$sha256)) stop("Original maps changed since bundle preparation.")
  }
  invisible(data.frame(status="PASS",files=nrow(manifest),bytes=sum(manifest$bytes),
    source_checked=!is.null(project),deletion_enabled=FALSE))
}

prepare_map_cleanup_recovery <- function(project=".", audit_dir="data/diagnostics/map-cleanup-audit") {
  if (!requireNamespace("digest",quietly=TRUE)) stop("The digest package is required for SHA-256 verification.")
  project <- normalizePath(project,winslash="/",mustWork=TRUE)
  audit <- normalizePath(file.path(project,audit_dir),winslash="/",mustWork=TRUE)
  if (!startsWith(tolower(audit),paste0(tolower(project),"/data/diagnostics/"))) stop("Audit must be inside project diagnostics.")
  report_paths <- file.path(audit,c("inventory.csv","proposed-cleanup.csv","scan-issues.csv"))
  if (!all(file.exists(report_paths))) stop("Audit reports are missing.")
  audit_hash <- map_recovery_sha(report_paths)
  inventory <- read.csv(report_paths[1],stringsAsFactors=FALSE)
  proposed <- read.csv(report_paths[2],stringsAsFactors=FALSE)
  issues <- read.csv(report_paths[3],stringsAsFactors=FALSE)
  if (nrow(issues)) stop("Audit has unresolved scan issues; no recovery bundle prepared.")
  if (!nrow(proposed)) stop("No review candidates in this audit.")
  required <- c("path","bytes","modified","status","reference_count","outside_project")
  if (!all(required %in% names(proposed)) || !all(required %in% names(inventory)) ||
      anyNA(proposed[,required]) || any(proposed$status != "REVIEW_CANDIDATE") ||
      any(proposed$reference_count != 0) || any(proposed$outside_project)) stop("Invalid candidate report.")
  index <- match(proposed$path,inventory$path)
  if (anyNA(index) || anyDuplicated(inventory$path) ||
      !all(vapply(required,function(key) identical(proposed[[key]],inventory[[key]][index]),logical(1))))
    stop("Proposed files differ from the audited inventory.")
  originals <- map_recovery_paths(project,proposed$path)
  info <- file.info(originals)
  if (any(info$size != proposed$bytes) || any(as.character(info$mtime) != proposed$modified))
    stop("Maps changed since audit (size or modification time). Rerun the audit.")
  message("Verified audit metadata for ",nrow(proposed)," files; computing content hashes...")
  hashes <- map_recovery_sha(originals)
  manifest <- data.frame(path=proposed$path,bytes=proposed$bytes,sha256=hashes,modified=proposed$modified)
  parent <- file.path(project,"data/diagnostics/map-cleanup-recovery")
  ancestor <- parent
  while(!dir.exists(ancestor)) ancestor <- dirname(ancestor)
  resolved <- normalizePath(ancestor,winslash="/",mustWork=TRUE)
  if (tolower(resolved) != tolower(ancestor)) stop("Recovery directory traverses a link.")
  dir.create(parent,recursive=TRUE,showWarnings=FALSE)
  run <- tempfile(paste0(format(Sys.time(),"%Y%m%dT%H%M%S",tz="UTC"),"-"),tmpdir=parent)
  dir.create(run)
  scratch <- tempfile("map-recovery-pack-");dir.create(scratch)
  on.exit(unlink(scratch,recursive=TRUE),add=TRUE)
  for(i in seq_along(originals)) {
    target <- file.path(scratch,manifest$path[i]);dir.create(dirname(target),recursive=TRUE,showWarnings=FALSE)
    if (!file.copy(originals[i],target,copy.date=TRUE)) stop("Could not copy recovery file.")
  }
  if (!identical(map_recovery_sha(file.path(scratch,manifest$path)),hashes)) stop("Recovery staging copy differs from originals.")
  manifest_file <- file.path(run,"restore-manifest.csv")
  write.csv(manifest,manifest_file,row.names=FALSE)
  file.copy(manifest_file,file.path(scratch,"restore-manifest.csv"))
  for(p in report_paths) file.copy(p,file.path(run,paste0("audit-",basename(p))))
  archive <- file.path(run,"recovery.tar.gz")
  message("Packing ",nrow(manifest)," files (",round(sum(manifest$bytes)/1024^2,1)," MiB)...")
  old <- setwd(scratch)
  archive_notes <- character()
  tryCatch(withCallingHandlers(
    utils::tar(archive,files=c("restore-manifest.csv",manifest$path),compression="gzip",tar="internal"),
    warning=function(w) {
      note <- conditionMessage(w)
      if (!startsWith(note,"storing paths of more than 100 bytes is not portable:"))
        stop("Archive creation warning: ",note)
      # R warns for long paths that its tar writer/reader can preserve. Retain
      # these notes, and still require the complete extraction/hash round trip.
      archive_notes <<- c(archive_notes,note)
      invokeRestart("muffleWarning")
    }),
    finally=setwd(old))
  if (!file.exists(archive) || file.info(archive)$size <= 0) stop("Recovery archive was not created.")
  if (!identical(map_recovery_sha(report_paths),audit_hash)) stop("Audit changed during preparation.")
  if(length(archive_notes))writeLines(archive_notes,file.path(run,"archive-notes.txt"))
  record <- list(schema_version=1L,status="VERIFIED_RECOVERY_ONLY",deletion_enabled=FALSE,
    project=project,created_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),
    files=nrow(manifest),original_bytes=sum(manifest$bytes),archive_bytes=file.info(archive)$size,
    archive_sha256=map_recovery_sha(archive),manifest_sha256=map_recovery_sha(manifest_file),
    audit_sha256=as.list(setNames(audit_hash,basename(report_paths))))
  jsonlite::write_json(record,file.path(run,"bundle.json"),auto_unbox=TRUE,pretty=TRUE)
  # Incomplete preparations have no READY marker. Never infer readiness solely
  # from an archive's presence, or from metadata written before verification.
  message("Verifying archive extraction and rechecking original files...")
  summary <- verify_map_cleanup_bundle(run,project=project,require_ready=FALSE)
  write.csv(summary,file.path(run,"verification.csv"),row.names=FALSE)
  writeLines(c("RECOVERY VERIFIED; DELETION DISABLED",paste("Files:",nrow(manifest)),
    "Original maps are unchanged. This bundle is not authorization to delete.",
    "Verify again before a future cleanup. External hotlinks were not audited.",
    "Archive paths are project-relative; restore-manifest.csv records SHA-256 and size.",
    "No automatic restore is provided: restore into a separate directory and verify before replacing maps.",
    "The original audit recorded size/time, not content hashes. SHA-256 protection begins at preparation."),
    file.path(run,"READY.txt"))
  print(summary,row.names=FALSE)
  message("Verified recovery bundle: ",run,"; deletion remains disabled.")
  invisible(list(directory=run,summary=summary,manifest=manifest))
}

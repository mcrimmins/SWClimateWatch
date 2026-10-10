# One-time Windows-to-VM seed transfer using native OpenSSH scp and ssh.
# Run from the project root in a terminal (not the RStudio R Console):
#   Rscript scripts/transfer-production-seed.R             # preview only
#   Rscript scripts/transfer-production-seed.R --execute   # copy and verify
# Re-running --execute skips directories already matching the laptop inventory.
# This script never deletes remote files and never runs the daily publisher.

swc_seed_groups <- c(
  "site/stations",
  "site/maps/generated",
  "data/diagnostics",
  "data/processed/acis-stations",
  "data/processed/snodas",
  "data/processed/prism",
  "data/raw/prism"
)

swc_seed_quote_local <- function(value) {
  shQuote(value, type = if (.Platform$OS.type == "windows") "cmd" else "sh")
}

swc_seed_quote_remote <- function(value) {
  paste0("'", gsub("'", "'\\''", value, fixed = TRUE), "'")
}

swc_seed_remote_shell <- function(command) {
  # Encoding keeps find's % directives and shell quotes away from Windows CMD.
  encoded <- jsonlite::base64_enc(charToRaw(command))
  paste("echo", swc_seed_quote_remote(encoded), "| base64 -d | sh")
}

swc_seed_inventory_local <- function(root, group) {
  directory <- file.path(root, group)
  if (!dir.exists(directory)) stop("Missing local seed directory: ", directory)
  directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
  files <- list.files(directory, recursive = TRUE, full.names = TRUE,
                      all.files = TRUE, no.. = TRUE)
  if (!length(files)) stop("Empty local seed directory: ", directory)
  paths <- gsub("\\\\", "/", files)
  relative <- substring(paths, nchar(directory) + 2L)
  result <- data.frame(path = relative,
                       size = as.numeric(file.info(files)$size),
                       local_path = paths, stringsAsFactors = FALSE)
  if (anyNA(result$size) || anyDuplicated(result$path)) {
    stop("Could not inventory local files in ", group)
  }
  result[order(result$path), , drop = FALSE]
}

swc_seed_samples <- function(inventory) {
  manifest <- which(inventory$path == "manifest.csv")
  largest <- which.max(inventory$size)
  selected <- unique(c(manifest, largest))
  inventory[selected, , drop = FALSE]
}

swc_seed_remote_state <- function(host, remote_root, group, samples) {
  remote_directory <- paste0(remote_root, "/", group)
  quoted_directory <- swc_seed_quote_remote(remote_directory)
  command <- paste0(
    "if [ -d ", quoted_directory, " ]; then find ", quoted_directory,
    " -type f -printf 'FILE\\t%P\\t%s\\n'; fi")
  for (path in samples$path) {
    remote_file <- paste0(remote_directory, "/", path)
    command <- paste0(
      command, "; printf 'HASH\\t%s\\t' ", swc_seed_quote_remote(path),
      "; if [ -f ", swc_seed_quote_remote(remote_file), " ]; then md5sum ",
      swc_seed_quote_remote(remote_file),
      " | cut -c1-32; else printf 'MISSING\\n'; fi")
  }
  output <- suppressWarnings(system2(
    "ssh", args = c("-o", "ConnectTimeout=10", host,
                    swc_seed_quote_local(swc_seed_remote_shell(command))),
    stdout = TRUE, stderr = ""))
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) {
    stop("Remote inventory failed for ", group, " (SSH status ", status, ").")
  }
  file_lines <- output[startsWith(output, "FILE\t")]
  hash_lines <- output[startsWith(output, "HASH\t")]
  files <- if (length(file_lines)) {
    parts <- strsplit(substring(file_lines, 6L), "\t", fixed = TRUE)
    if (any(lengths(parts) != 2L)) stop("Malformed remote inventory for ", group)
    data.frame(path = vapply(parts, `[[`, character(1), 1L),
               size = as.numeric(vapply(parts, `[[`, character(1), 2L)),
               stringsAsFactors = FALSE)
  } else data.frame(path = character(), size = numeric())
  hashes <- if (length(hash_lines)) {
    parts <- strsplit(substring(hash_lines, 6L), "\t", fixed = TRUE)
    if (any(lengths(parts) != 2L)) stop("Malformed remote hashes for ", group)
    stats::setNames(vapply(parts, `[[`, character(1), 2L),
                    vapply(parts, `[[`, character(1), 1L))
  } else character()
  list(files = files, hashes = hashes)
}

swc_seed_matches <- function(local, samples, remote) {
  positions <- match(local$path, remote$files$path)
  sizes_match <- all(!is.na(positions)) &&
    all(local$size == remote$files$size[positions])
  if (!sizes_match) return(FALSE)
  if (!all(samples$path %in% names(remote$hashes))) return(FALSE)
  local_hashes <- unname(tools::md5sum(samples$local_path))
  identical(unname(remote$hashes[samples$path]), local_hashes)
}

swc_transfer_production_seed <- function(
    dry_run = TRUE, root = getwd(),
    host = Sys.getenv("SWC_VM_SSH_HOST", "crimmins@10.222.142.128"),
    remote_root = "/home/crimmins/RProjects/SWClimateWatch") {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!file.exists(file.path(root, "site", "_quarto.yml"))) {
    stop("Run this script from the SWClimateWatch project root.")
  }
  original_directory <- getwd()
  on.exit(setwd(original_directory), add = TRUE)
  setwd(root)
  if (!grepl("^[[:alnum:]_.-]+@[[:alnum:].-]+$", host)) {
    stop("SWC_VM_SSH_HOST must be a user@host SSH destination.")
  }
  if (!identical(remote_root, "/home/crimmins/RProjects/SWClimateWatch")) {
    stop("Unexpected VM destination; this script is scoped to SWClimateWatch.")
  }
  if (!dry_run && (!nzchar(Sys.which("scp")) || !nzchar(Sys.which("ssh")))) {
    stop("Native scp and ssh must be available on PATH.")
  }
  results <- vector("list", length(swc_seed_groups))
  for (index in seq_along(swc_seed_groups)) {
    group <- swc_seed_groups[[index]]
    local <- swc_seed_inventory_local(root, group)
    samples <- swc_seed_samples(local)
    gb <- sum(local$size) / 1024^3
    message(sprintf("[%d/%d] %s: %d files, %.2f GiB", index,
                    length(swc_seed_groups), group, nrow(local), gb))
    if (dry_run) {
      state <- "PREVIEW"
    } else {
      remote <- swc_seed_remote_state(host, remote_root, group, samples)
      if (swc_seed_matches(local, samples, remote)) {
        state <- "SKIPPED_VERIFIED"
      } else {
        remote_parent <- paste0(remote_root, "/", dirname(group))
        mkdir_command <- paste("mkdir -p", swc_seed_quote_remote(remote_parent))
        mkdir_status <- system2(
          "ssh", args = c("-o", "ConnectTimeout=10", host,
                          swc_seed_quote_local(swc_seed_remote_shell(mkdir_command))),
          stdout = "", stderr = "")
        if (!identical(as.integer(mkdir_status), 0L)) {
          stop("Could not create VM parent directory for ", group)
        }
        # A relative source matches the native Windows scp form already tested.
        source_path <- group
        destination <- paste0(host, ":", remote_parent, "/")
        message("  Copying; SSH may request your VM password...")
        copy_status <- system2(
          "scp", args = c("-rp", swc_seed_quote_local(source_path),
                          swc_seed_quote_local(destination)),
          stdout = "", stderr = "")
        if (!identical(as.integer(copy_status), 0L)) {
          stop("SCP failed for ", group, ". Re-run --execute to retry.")
        }
        remote <- swc_seed_remote_state(host, remote_root, group, samples)
        if (!swc_seed_matches(local, samples, remote)) {
          stop("Verification failed for ", group,
               ". Check VM contents before retrying.")
        }
        state <- "COPIED_VERIFIED"
      }
    }
    message("  ", state)
    results[[index]] <- data.frame(group = group, files = nrow(local),
                                   gib = round(gb, 3), status = state,
                                   stringsAsFactors = FALSE)
  }
  result <- do.call(rbind, results)
  if (dry_run) {
    message("Preview only: no files transferred. Run with --execute to copy.")
  } else {
    message("Seed transfer verified. Next: run check-production-readiness.R on the VM.")
  }
  result
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 1L || (length(args) == 1L &&
      !args[[1L]] %in% c("--execute", "--dry-run"))) {
    stop("Usage: Rscript scripts/transfer-production-seed.R [--execute|--dry-run]")
  }
  print(swc_transfer_production_seed(dry_run = !identical(args, "--execute")),
        row.names = FALSE)
}

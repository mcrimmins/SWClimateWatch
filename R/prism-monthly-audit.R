# Full-cache audit. All operations are local and inputs are read-only.
prism_monthly_input_signature <- function(audit, variables, months) {
  rows <- audit$plan[audit$plan$variable %in% variables & audit$plan$month %in% months, ]
  if (!nrow(rows) || !all(rows$complete)) stop("Unverified product dependency inputs.")
  hashes <- if ("md5" %in% names(rows)) rows$md5 else unname(tools::md5sum(rows$path))
  digest::digest(list(month = as.character(rows$month), variable = as.character(rows$variable),
    request = as.character(rows$request_signature), md5 = unname(hashes)), algo = "sha256")
}

prism_monthly_slice_audit <- function(audit, end) {
  result <- audit
  result$plan <- audit$plan[audit$plan$month <= end, ]
  result$months <- audit$months[audit$months$month <= end, ]
  result$summary$end_month <- end
  result$summary$expected_inputs <- nrow(result$plan)
  result$summary$months <- nrow(result$months)
  result
}

prism_monthly_source_signature <- function(audit) {
  # CSV reuse can change data-frame row-name attributes without changing inputs.
  digest::digest(list(month = unname(as.character(audit$months$month)),
    signature = unname(as.character(audit$months$signature))), algo = "sha256")
}

write_prism_monthly_audit_report <- function(data, path) {
  temporary <- tempfile("monthly-audit-", tmpdir = dirname(path), fileext = ".csv")
  on.exit(unlink(temporary), add = TRUE)
  utils::write.csv(data, temporary, row.names = FALSE)
  replace_file_atomically(temporary, path)
}

prism_monthly_audit_signature <- function(rows, reference) {
  digest::digest(list(policy = "monthly-audit-v1", reference = reference,
    rows = rows[, c("month", "variable", "request_signature", "complete")],
    md5 = unname(tools::md5sum(rows$path))), algo = "sha256")
}

audit_prism_monthly_cache <- function(start = "1895-01",
    end = prism_monthly_latest_complete(), cache_dir = prism_monthly_cache_dir(),
    report_dir = "data/diagnostics/prism-monthly-cache-audit", bbox = swc_region$bbox) {
  started <- proc.time()[["elapsed"]]
  plan <- plan_prism_monthly_download(start = start, end = end,
    cache_dir = cache_dir, bbox = bbox, verify_grids = FALSE)
  months <- unique(plan$month)
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(report_dir, "months.csv")
  previous <- if (file.exists(path)) read.csv(path, stringsAsFactors = FALSE) else data.frame()
  first <- which(plan$complete)[1]
  reference <- if (!is.na(first)) terra::rast(plan$path[first]) else NULL
  geometry <- if (!is.null(reference)) list(extent = as.vector(terra::ext(reference)),
    resolution = terra::res(reference), dimensions = dim(reference), crs = terra::crs(reference)) else NULL
  records <- vector("list", length(months)); reused <- 0L
  for (i in seq_along(months)) {
    rows <- plan[plan$month == months[i], ]
    signature <- prism_monthly_audit_signature(rows, geometry)
    old <- if (nrow(previous)) previous[previous$month == months[i] &
      previous$signature == signature & previous$status %in% c("PASS", "WARN"), , drop = FALSE] else data.frame()
    if (nrow(old) == 1L) {
      records[[i]] <- old; reused <- reused + 1L
    } else {
      record <- data.frame(month = months[i], signature = signature, status = "FAIL",
        min_valid_fraction = NA_real_, max_valid_fraction = NA_real_,
        max_below_min_cells = NA_real_, one_sided_temperature_cells = NA_real_, note = "")
      records[[i]] <- tryCatch({
        if (!all(rows$complete)) stop("Missing, changed-request or checksum-mismatched input.")
        checked <- lapply(seq_len(nrow(rows)), function(j) {
          validate_prism_monthly_grid(rows$path[j], rows[j, ], reference)
        })
        hi <- checked[[match("maxt", rows$variable)]]$raster
        lo <- checked[[match("mint", rows$variable)]]$raster
        record$max_below_min_cells <- terra::global(hi < lo, "sum", na.rm = TRUE)[1, 1]
        record$one_sided_temperature_cells <- terra::global(xor(is.na(hi), is.na(lo)), "sum")[1, 1]
        fractions <- vapply(checked, function(x) x$valid_fraction, numeric(1))
        record$min_valid_fraction <- min(fractions)
        record$max_valid_fraction <- max(fractions)
        if (record$max_below_min_cells > 0) stop("Monthly maximum below minimum temperature.")
        record$status <- if (record$one_sided_temperature_cells > 0) "WARN" else "PASS"
        if (record$status == "WARN") record$note <- "Unpaired temperature cells; exclude from derived means."
        record
      }, error = function(e) { record$note <- conditionMessage(e); record })
    }
    if (i %% 25L == 0L || i == length(months)) {
      write_prism_monthly_audit_report(do.call(rbind, records[seq_len(i)]), path)
      message("Monthly cache audit: ", i, "/", length(months), " months; ", reused, " reused.")
    }
  }
  records <- do.call(rbind, records)
  summary <- data.frame(status = if (any(records$status == "FAIL")) "FAIL" else
      if (any(records$status == "WARN")) "WARN" else "PASS",
    start_month = start, end_month = end, expected_inputs = nrow(plan),
    checksum_verified_inputs = sum(plan$complete), months = length(months),
    failed_months = sum(records$status == "FAIL"), warning_months = sum(records$status == "WARN"),
    temperature_pair_failures = sum(records$max_below_min_cells, na.rm = TRUE),
    one_sided_temperature_cells = sum(records$one_sided_temperature_cells, na.rm = TRUE),
    reused_months = reused, saved_gib = sum(file.info(plan$path)$size, na.rm = TRUE) / 1024^3,
    elapsed_seconds = proc.time()[["elapsed"]] - started)
  write_prism_monthly_audit_report(summary, file.path(report_dir, "summary.csv"))
  list(summary = summary, months = records, plan = plan)
}

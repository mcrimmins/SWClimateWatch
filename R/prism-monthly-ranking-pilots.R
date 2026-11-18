# Local review batch: one audit, separate output folders, checksummed completion.
prism_monthly_ranking_complete <- function(path, signature) {
  if (!file.exists(path)) return(FALSE)
  marker <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.list(marker) || !identical(marker$signature, signature) ||
      is.null(marker$files) || !length(marker$files) || !all(file.exists(marker$files))) return(FALSE)
  hashes <- unname(tools::md5sum(marker$files))
  !anyNA(hashes) && identical(hashes, marker$md5)
}

prism_monthly_ranking_gallery <- function(results, root, end) {
  # Values below are generated date/duration/variable labels, not external HTML.
  selected <- results[results$status == "READY" & nzchar(results$map), ]
  cards <- vapply(seq_len(nrow(selected)), function(i) {
    row <- selected[i, ]
    src <- paste(end, row$variable, sprintf("%02dmonth", row$duration_months),
      paste0(row$variable, "-ranking.png"), sep = "/")
    paste0('<article><h2>', row$duration_months, '-month ', row$variable,
      '</h2><a href="', src, '" target="_blank"><img loading="lazy" src="', src,
      '" alt="', row$duration_months, '-month ', row$variable, ' ranking"></a></article>')
  }, character(1))
  path <- file.path(root, "index.html")
  html <- c('<!doctype html><html lang="en"><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Monthly PRISM ranking pilots</title><style>',
    'body{font-family:system-ui,sans-serif;background:#f1f4f4;color:#24363f;margin:24px auto;max-width:1500px;padding:0 16px}',
    '.maps{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}',
    'article{background:white;border:1px solid #ccd5da;border-radius:8px;padding:10px}h2{font-size:18px;margin:4px 0 8px}img{width:100%;height:auto}',
    '@media(max-width:850px){.maps{grid-template-columns:1fr}}</style>',
    paste0('<h1>Monthly PRISM rankings through ', end, '</h1>'),
    '<p>Local review only. Click an image for full resolution. Temperature uses day-weighted means; precipitation uses sums. Both compare matching full-record windows. Precipitation rankings are not SPI.</p>',
    '<div class="maps">', cards, '</div></html>')
  writeLines(html, path)
  path
}

build_prism_monthly_ranking_pilots <- function(end = prism_monthly_latest_complete(),
    temperature_durations = c(1L, 3L, 6L, 12L), precipitation_durations = c(1L, 3L, 6L, 12L),
    start = "1895-01", cache_dir = prism_monthly_cache_dir(),
    output_dir = "data/diagnostics/prism-monthly-ranking-pilots",
    audit_dir = "data/diagnostics/prism-monthly-cache-audit", bbox = swc_region$bbox,
    min_years = 30L, min_fraction = 0.9, make_maps = TRUE, force = FALSE, .audit = NULL) {
  started <- proc.time()[["elapsed"]]
  durations <- c(temperature_durations, precipitation_durations)
  if (!length(durations) || anyNA(durations) || any(!is.finite(durations)) ||
      any(durations < 1 | durations > .Machine$integer.max | durations != floor(durations))) {
    stop("Supply positive whole-month durations.")
  }
  temperature_durations <- as.integer(temperature_durations)
  precipitation_durations <- as.integer(precipitation_durations)
  audit <- prism_monthly_pilot_audit(start, end, cache_dir, audit_dir, bbox, .audit)
  source_signature <- prism_monthly_source_signature(audit)
  jobs <- rbind(data.frame(variable = rep("temperature", length(unique(temperature_durations))),
      duration_months = unique(temperature_durations)),
    data.frame(variable = rep("precipitation", length(unique(precipitation_durations))),
      duration_months = unique(precipitation_durations)))
  # Put temperature then precipitation next to each other for each duration.
  jobs <- jobs[order(jobs$duration_months, match(jobs$variable, c("temperature", "precipitation"))), ]
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  records <- list()
  for (i in seq_len(nrow(jobs))) {
    job <- jobs[i, ]; tick <- proc.time()[["elapsed"]]
    folder <- file.path(output_dir, end, job$variable, sprintf("%02dmonth", job$duration_months))
    marker_path <- file.path(folder, "complete.rds")
    dependencies <- prism_monthly_ranking_dependencies(start, end, job$duration_months)
    product_source <- prism_monthly_input_signature(audit,
      if (job$variable == "temperature") c("maxt", "mint") else "pcpn", dependencies)
    signature <- digest::digest(list(policy = "monthly-ranking-pilots-v3.1-record-both-zero02", source = product_source,
      variable = job$variable, duration = job$duration_months, start = start, end = end,
      min_years = min_years, min_fraction = min_fraction, make_maps = make_maps), algo = "sha256")
    message("Monthly ranking pilot ", i, "/", nrow(jobs), ": ", job$variable, " ", job$duration_months, " months.")
    row <- tryCatch({
      reused <- !isTRUE(force) && prism_monthly_ranking_complete(marker_path, signature)
      if (reused) {
        result <- readRDS(marker_path)$result
      } else {
        builder <- if (job$variable == "temperature") build_prism_monthly_temperature_pilot else build_prism_monthly_precipitation_pilot
        result <- builder(end = end, duration = job$duration_months, start = start, cache_dir = cache_dir,
          output_dir = folder, audit_dir = audit_dir, bbox = bbox,
          min_years = min_years, min_fraction = min_fraction, make_map = make_maps, .audit = audit)
        files <- list.files(folder, full.names = TRUE)
        files <- files[basename(files) != "complete.rds"]
        saveRDS(list(signature = signature, files = files, md5 = unname(tools::md5sum(files)), result = result), marker_path)
      }
      data.frame(variable = job$variable, duration_months = job$duration_months,
        status = "READY", event = if (reused) "REUSED" else "BUILT",
        comparison_windows = result$summary$comparison_windows,
        supported_cells = result$summary$supported_cells,
        current_valid_cells = result$summary$current_valid_cells,
        record_high_cells = result$summary$record_high_cells,
        tied_record_high_cells = result$summary$tied_record_high_cells,
        record_low_cells = result$summary$record_low_cells,
        tied_record_low_cells = result$summary$tied_record_low_cells,
        map = if (make_maps) result$paths[["map"]] else "", note = "")
    }, error = function(e) data.frame(variable = job$variable, duration_months = job$duration_months,
      status = "FAILED", event = "FAILED", comparison_windows = NA_integer_,
      supported_cells = NA_integer_, current_valid_cells = NA_integer_, record_high_cells = NA_integer_,
      tied_record_high_cells = NA_integer_, record_low_cells = NA_integer_,
      tied_record_low_cells = NA_integer_, map = "", note = conditionMessage(e)))
    row$elapsed_seconds <- proc.time()[["elapsed"]] - tick
    records[[i]] <- row
    write_prism_monthly_audit_report(do.call(rbind, records), file.path(output_dir, "last-batch.csv"))
  }
  results <- do.call(rbind, records)
  gallery <- if (make_maps && all(results$status == "READY")) prism_monthly_ranking_gallery(results, output_dir, end) else NA_character_
  summary <- data.frame(status = if (all(results$status == "READY")) "READY" else "PARTIAL",
    end_month = end, products = nrow(results), built = sum(results$event == "BUILT"),
    reused = sum(results$event == "REUSED"), failed = sum(results$status == "FAILED"),
    elapsed_seconds = proc.time()[["elapsed"]] - started, source_signature = source_signature)
  write_prism_monthly_audit_report(summary, file.path(output_dir, "summary.csv"))
  list(summary = summary, results = results, gallery = gallery)
}

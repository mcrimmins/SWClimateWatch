# Local SPI pilot: mixed-zero gamma MLE, fixed calendar-matched calibration.
prism_monthly_spi_policy <- function() list(version = "gamma-mle-classic-zero-v1",
  calibration_start = 1895L, calibration_end = 2020L, min_years = 50L,
  min_fraction = 0.9, min_positive = 30L, max_zero_fraction = 0.5,
  max_positive_cdf_error = 0.15, probability_epsilon = 1e-10)

prism_monthly_spi_dependencies <- function(start, end, duration, policy = prism_monthly_spi_policy()) {
  cal_end <- sprintf("%04d-%s", policy$calibration_end, substr(end, 6, 7))
  windows <- prism_monthly_comparison_windows(start, cal_end, duration)
  windows <- windows[windows$ending_year >= policy$calibration_start, ]
  unique(c(format(prism_monthly_window(end, duration), "%Y-%m"),
    unlist(lapply(windows$ending_month, function(e) format(prism_monthly_window(e, duration), "%Y-%m")))))
}

prism_monthly_spi_status_labels <- c("OK", "INSUFFICIENT_HISTORY", "TOO_FEW_POSITIVES",
  "COMMON_ZEROS", "CONSTANT_POSITIVES", "FIT_FAILED", "CURRENT_UNAVAILABLE", "CDF_MISMATCH")

validate_prism_monthly_spi_policy <- function(policy) {
  required <- names(prism_monthly_spi_policy())
  if (!is.list(policy) || !all(required %in% names(policy))) stop("Incomplete SPI policy.")
  numbers <- unlist(policy[setdiff(required, "version")], use.names = FALSE)
  if (length(numbers) != length(required) - 1L || any(!is.finite(numbers)) ||
      policy$calibration_start > policy$calibration_end || policy$min_years < 2 || policy$min_positive < 2 ||
      policy$min_fraction <= 0 || policy$min_fraction > 1 ||
      policy$max_zero_fraction <= 0 || policy$max_zero_fraction > 1 ||
      policy$max_positive_cdf_error <= 0 || policy$max_positive_cdf_error > 1 ||
      policy$probability_epsilon <= 0 || policy$probability_epsilon >= .5) stop("Invalid SPI policy thresholds.")
  invisible(TRUE)
}

fit_prism_monthly_spi_gamma <- function(values, policy = prism_monthly_spi_policy()) {
  validate_prism_monthly_spi_policy(policy)
  if (!is.matrix(values) || !nrow(values) || !ncol(values)) stop("Expected cell-by-year calibration matrix.")
  if (any(values < 0, na.rm = TRUE)) stop("SPI precipitation cannot be negative.")
  values[!is.finite(values)] <- NA_real_
  n <- rowSums(!is.na(values)); zeros <- rowSums(values == 0, na.rm = TRUE)
  positive <- values; positive[is.na(positive) | positive <= 0] <- NA_real_
  np <- rowSums(!is.na(positive)); q <- zeros / pmax(n, 1)
  mu <- rowMeans(positive, na.rm = TRUE)
  a <- log(mu) - rowMeans(log(positive), na.rm = TRUE)
  status <- rep(0L, nrow(values))
  status[n < max(policy$min_years, ceiling(policy$min_fraction * ncol(values)))] <- 1L
  status[status == 0L & q >= policy$max_zero_fraction] <- 3L
  status[status == 0L & np < policy$min_positive] <- 2L
  status[status == 0L & (!is.finite(a) | a <= 1e-12 | !is.finite(mu) | mu <= 0)] <- 4L
  shape <- scale <- cdf_error <- rep(NA_real_, length(n))
  good <- which(status == 0L)
  if (length(good)) {
    aa <- a[good]
    alpha <- (1 + sqrt(1 + 4 * aa / 3)) / (4 * aa)
    converged <- rep(FALSE, length(good))
    for (iteration in 1:60) {
      proposed <- alpha - (log(alpha) - digamma(alpha) - aa) / (1 / alpha - trigamma(alpha))
      invalid <- !is.finite(proposed) | proposed <= 0
      proposed[invalid] <- alpha[invalid] / 2
      converged <- abs(proposed - alpha) <= 1e-9 * pmax(1, alpha)
      alpha <- proposed
      if (all(converged)) break
    }
    valid <- converged & is.finite(alpha) & alpha > 0 & alpha <= 1e8
    status[good[!valid]] <- 5L
    good <- good[valid]; alpha <- alpha[valid]
    shape[good] <- alpha; scale[good] <- mu[good] / alpha
    if (length(good)) {
      sorted <- t(apply(positive[good, , drop = FALSE], 1, sort, na.last = TRUE))
      # Fitted-parameter KS-style distance on positive amounts, not a KS p-value.
      fitted <- matrix(stats::pgamma(as.vector(sorted), shape = rep(shape[good], ncol(sorted)),
        scale = rep(scale[good], ncol(sorted))), nrow = length(good))
      order <- matrix(rep(seq_len(ncol(sorted)), each = length(good)), nrow = length(good))
      denominator <- pmax(np[good], 1)
      upper <- order / denominator; lower <- (order - 1) / denominator
      error <- pmax(upper - fitted, fitted - lower)
      cdf_error[good] <- apply(error, 1, max, na.rm = TRUE)
      bad <- good[!is.finite(cdf_error[good]) | cdf_error[good] > policy$max_positive_cdf_error]
      status[bad] <- 7L
    }
  }
  data.frame(shape = shape, scale_inches = scale, zero_fraction = ifelse(n > 0, q, NA_real_),
    sample_years = n, positive_years = np, positive_cdf_error = cdf_error, fit_status = status)
}

evaluate_prism_monthly_spi <- function(current, fit, policy = prism_monthly_spi_policy()) {
  if (length(current) != nrow(fit)) stop("SPI fit and current grid lengths differ.")
  status <- fit$fit_status
  status[status == 0L & (!is.finite(current) | current < 0)] <- 6L
  spi <- probability <- rep(NA_real_, length(current)); clipped <- rep(NA_real_, length(current))
  ok <- which(status == 0L)
  if (length(ok)) {
    p <- fit$zero_fraction[ok] + (1 - fit$zero_fraction[ok]) * stats::pgamma(current[ok],
      shape = fit$shape[ok], scale = fit$scale_inches[ok])
    probability[ok] <- p
    clipped[ok] <- as.numeric(p < policy$probability_epsilon | p > 1 - policy$probability_epsilon)
    spi[ok] <- stats::qnorm(pmin(1 - policy$probability_epsilon, pmax(policy$probability_epsilon, p)))
  }
  data.frame(spi = spi, mixed_probability = probability, probability_clipped = clipped, spi_status = status)
}

prism_monthly_spi_display <- function(spi, land) {
  result <- rep(NA_real_, length(spi))
  result[land & !is.finite(spi)] <- 8
  good <- is.finite(spi)
  result[good & spi <= -2] <- 1
  result[good & spi > -2 & spi <= -1.5] <- 2
  result[good & spi > -1.5 & spi <= -1] <- 3
  result[good & spi > -1 & spi < 1] <- 4
  result[good & spi >= 1 & spi < 1.5] <- 5
  result[good & spi >= 1.5 & spi < 2] <- 6
  result[good & spi >= 2] <- 7
  result
}

validate_prism_monthly_spi_methods <- function() {
  if (!requireNamespace("MASS", quietly = TRUE)) stop("Install the recommended R package MASS for independent SPI method checks.")
  policy <- prism_monthly_spi_policy()
  records <- lapply(c(0.6, 2, 8), function(shape) {
    x <- stats::qgamma((seq_len(150) - 0.5) / 150, shape = shape, scale = 2)
    fitted <- fit_prism_monthly_spi_gamma(matrix(x, nrow = 1), policy)
    moment_shape <- mean(x)^2 / stats::var(x)
    reference <- suppressWarnings(MASS::fitdistr(x, "gamma",
      start = list(shape = moment_shape, rate = moment_shape / mean(x)), control = list(reltol = 1e-12)))
    expected <- c(shape = reference$estimate[["shape"]], scale_inches = 1 / reference$estimate[["rate"]])
    actual <- c(shape = fitted$shape, scale_inches = fitted$scale_inches)
    error <- max(abs(actual - expected) / pmax(abs(expected), 1e-10))
    data.frame(scenario = paste0("Independent gamma MLE, shape ", shape),
      status = if (fitted$fit_status == 0 && error < 1e-3) "PASS" else "FAIL", maximum_relative_error = error)
  })
  x <- c(rep(0, 15), stats::qgamma((seq_len(135) - .5) / 135, shape = 2, scale = 2))
  fitted <- fit_prism_monthly_spi_gamma(matrix(x, nrow = 1), policy)
  z <- evaluate_prism_monthly_spi(0, fitted, policy)$spi
  records[[4]] <- data.frame(scenario = "Classic zero mass transformation",
    status = if (is.finite(z) && abs(z - stats::qnorm(.1)) < 1e-10) "PASS" else "FAIL", maximum_relative_error = abs(z - stats::qnorm(.1)))
  do.call(rbind, records)
}

build_prism_monthly_spi_pilots <- function(end = prism_monthly_latest_complete(), durations = c(1L, 3L, 6L, 12L),
    cache_dir = prism_monthly_cache_dir(), output_dir = "data/diagnostics/prism-monthly-spi-pilots",
    fit_dir = file.path(cache_dir, "spi-fits"), audit_dir = "data/diagnostics/prism-monthly-cache-audit",
    bbox = swc_region$bbox, make_maps = TRUE, force = FALSE,
    start = "1895-01", policy = prism_monthly_spi_policy(), .audit = NULL) {
  started <- proc.time()[["elapsed"]]
  validate_prism_monthly_spi_policy(policy)
  if (!length(durations) || anyNA(durations) || any(!is.finite(durations)) ||
      any(durations < 1 | durations > .Machine$integer.max | durations != floor(durations))) stop("Invalid SPI durations.")
  durations <- unique(as.integer(durations))
  target <- prism_monthly_month(end)
  if (as.integer(format(target, "%Y")) < policy$calibration_end) stop("Pilot target must reach the fixed calibration end year.")
  methods <- validate_prism_monthly_spi_methods()
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(policy, file.path(output_dir, "method-policy.json"), auto_unbox = TRUE, pretty = TRUE)
  writeLines(c("SPI pilot: calendar-matched monthly precipitation sums, zero-adjusted two-parameter gamma MLE.",
    "Fixed calibration ends in 2020; current values after 2020 do not enter the fit.",
    "MLE fits positive amounts. Zero probability q uses all nonmissing calibration totals.",
    "Mixed probability H(x)=q+(1-q)*pgamma(x,shape,scale); SPI=qnorm(H(x)).",
    "Classic zero convention H(0)=q. Common-zero periods (q>=0.5) are withheld.",
    "Require at least 50 years, 90% of eligible calibration windows, and 30 positive totals by default.",
    "Positive-sample fitted-CDF distance >0.15 is a conservative pilot guard, not a formal KS p-value.",
    "Nonconvergent/constant/unsupported fits are withheld, never replaced by precipitation z-scores or ranks.",
    "Probabilities are bounded to [1e-10,1-1e-10] for numerical inversion; clipped cells are flagged.",
    "Scientific SPI is not clipped to the map color range. Display class codes 1-8 are not SPI values.",
    "Reference fitting is scale invariant: inches and millimeters give the same SPI.",
    "SPI measures precipitation anomalies only, not temperature demand, streamflow or official drought categories.",
    "Independent method validation uses MASS gamma optimization and an explicit zero-mass check.",
    "Sources: https://climatedataguide.ucar.edu/climate-data/standardized-precipitation-index-spi",
    "https://www.ncl.ucar.edu/Applications/spi.shtml",
    "https://climate-indices.readthedocs.io/en/stable/reference.html"), file.path(output_dir, "methods.txt"))
  write_prism_monthly_audit_report(methods, file.path(output_dir, "method-checks.csv"))
  if (any(methods$status != "PASS")) stop("Independent SPI method checks failed; no maps built.")
  audit <- prism_monthly_pilot_audit(start, end, cache_dir, audit_dir, bbox, .audit)
  source_signature <- prism_monthly_source_signature(audit)
  reference <- terra::rast(audit$plan$path[1]); results <- list()
  for (duration in durations) {
    tick <- proc.time()[["elapsed"]]
    message("SPI pilot: ", duration, " months ending ", end)
    folder <- file.path(output_dir, end, sprintf("%02dmonth", duration)); dir.create(folder, recursive = TRUE, showWarnings = FALSE)
    complete <- file.path(folder, "complete.rds")
    product_source <- prism_monthly_input_signature(audit, "pcpn",
      prism_monthly_spi_dependencies(start, end, duration, policy))
    signature <- digest::digest(list(policy = policy, source = product_source, end = end,
      duration = duration, maps = make_maps, display = "spi-seven-classes-v1"), algo = "sha256")
    row <- tryCatch({
      if (!force && prism_monthly_ranking_complete(complete, signature)) {
        row <- readRDS(complete)$row; row$event <- "REUSED"; row$fit_reused <- TRUE
      } else {
        cal_end <- sprintf("%04d-%s", policy$calibration_end, format(target, "%m"))
        windows <- prism_monthly_comparison_windows(start, cal_end, duration)
        windows <- windows[windows$ending_year >= policy$calibration_start, ]
        dependencies <- unique(unlist(lapply(windows$ending_month,
          function(e) format(prism_monthly_window(e, duration), "%Y-%m"))))
        dependencies <- audit$months[audit$months$month %in% dependencies, ]
        fit_signature <- digest::digest(list(policy = policy, duration = duration, ending_month = format(target, "%m"),
          sources = prism_monthly_source_signature(list(months = dependencies))), algo = "sha256")
        fit_folder <- file.path(fit_dir, sprintf("cal%d-%d", policy$calibration_start, policy$calibration_end),
          format(target, "%m"), sprintf("%02dmonth", duration))
        fit_marker <- file.path(fit_folder, "complete.rds")
        fit_reused <- prism_monthly_ranking_complete(fit_marker, fit_signature)
        if (fit_reused) {
          fit <- readRDS(file.path(fit_folder, "fit.rds"))
        } else {
          values <- matrix(NA_real_, nrow = terra::ncell(reference), ncol = nrow(windows))
          for (i in seq_len(nrow(windows))) {
            values[, i] <- terra::values(prism_monthly_precipitation_window(audit$plan, windows$ending_month[i], duration), mat = FALSE)
            if (i %% 25L == 0 || i == nrow(windows)) message("SPI calibration: ", i, "/", nrow(windows), " matching windows.")
          }
          fit <- fit_prism_monthly_spi_gamma(values, policy)
          rm(values)
          dir.create(fit_folder, recursive = TRUE, showWarnings = FALSE)
          saveRDS(fit, file.path(fit_folder, "fit.rds"))
          write.csv(windows, file.path(fit_folder, "calibration-windows.csv"), row.names = FALSE)
          files <- file.path(fit_folder, c("fit.rds", "calibration-windows.csv"))
          saveRDS(list(signature = fit_signature, policy = policy, files = files,
            md5 = unname(tools::md5sum(files))), fit_marker)
        }
        current <- terra::values(prism_monthly_precipitation_window(audit$plan, end, duration), mat = FALSE)
        evaluated <- evaluate_prism_monthly_spi(current, fit, policy)
        land <- fit$sample_years > 0 | is.finite(current)
        output <- cbind(data.frame(total_precipitation_inches = current), evaluated, fit)
        output$display_class <- prism_monthly_spi_display(output$spi, land)
        for (name in names(output)) {
          r <- terra::setValues(reference, output[[name]]); names(r) <- name; terra::time(r) <- target
          terra::writeRaster(r, file.path(folder, paste0(name, ".tif")), overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
        }
        qc <- data.frame(code = 0:7, reason = prism_monthly_spi_status_labels,
          cells = vapply(0:7, function(code) sum(evaluated$spi_status[land] == code), numeric(1)))
        write.csv(qc, file.path(folder, "qc-counts.csv"), row.names = FALSE)
        write.csv(windows, file.path(folder, "calibration-windows.csv"), row.names = FALSE)
        valid <- is.finite(output$spi)
        if (!any(valid)) stop("No SPI cells passed support and fit checks; see qc-counts.csv.")
        map_path <- if (make_maps) file.path(folder, "spi.png") else ""
        if (make_maps) {
          period <- if (duration == 1) format(target, "%B %Y") else paste0(format(min(prism_monthly_window(end, duration)), "%B %Y"), "-", format(target, "%B %Y"))
          plot <- southwest_raster_map(terra::rast(file.path(folder, "display_class.tif")),
            states = southwest_state_boundaries(), counties = southwest_county_boundaries(),
            countries = southwest_country_boundaries(), cities = southwest_reference_cities(),
            title = paste0(duration, "-month Standardized Precipitation Index"),
            subtitle = paste0(period, " | calibration: matching windows ending ", min(windows$ending_year), "-", policy$calibration_end),
            caption = NULL, fill_label = "SPI (negative = drier; positive = wetter)",
            palette = c("#8c510a", "#bf812d", "#dfc27d", "#f5f5f5", "#80cdc1", "#35978f", "#01665e", "#bdbdbd"),
            palette_values = 1:8, limits = c(.5, 8.5), breaks = seq(.5, 8.5, by = 1),
            product_id = "monthly_spi", scale_type = "categorical")
          save_southwest_map(plot, map_path, logo_path = southwest_brand_logo_path(),
            footer_text = paste0("Data: PRISM Climate Group via RCC-ACIS\nGamma MLE; fixed ",
              policy$calibration_start, "-", policy$calibration_end,
              " calibration; zero-adjusted\nGray: insufficient support, common zeros or poor fit | Local pilot"))
        }
        row <- data.frame(duration_months = duration, status = "READY", event = "BUILT", fit_reused = fit_reused,
          calibration_windows = nrow(windows), current_valid_cells = sum(is.finite(current)),
          spi_valid_cells = sum(valid), withheld_cells = sum(land & !valid),
          tail_clipped_cells = sum(output$probability_clipped == 1, na.rm = TRUE), map = map_path, note = "")
        write.csv(row, file.path(folder, "summary.csv"), row.names = FALSE)
        files <- list.files(folder, full.names = TRUE); files <- files[basename(files) != "complete.rds"]
        saveRDS(list(signature = signature, files = files, md5 = unname(tools::md5sum(files)), row = row), complete)
      }
      row
    }, error = function(e) data.frame(duration_months = duration, status = "FAILED", event = "FAILED", fit_reused = NA,
      calibration_windows = NA_integer_, current_valid_cells = NA_integer_, spi_valid_cells = NA_integer_,
      withheld_cells = NA_integer_, tail_clipped_cells = NA_integer_, map = "", note = conditionMessage(e)))
    row$elapsed_seconds <- proc.time()[["elapsed"]] - tick
    results[[length(results) + 1L]] <- row
    write_prism_monthly_audit_report(do.call(rbind, results), file.path(output_dir, "last-batch.csv"))
  }
  results <- do.call(rbind, results)
  summary <- data.frame(status = if (all(results$status == "READY")) "READY" else "PARTIAL", end_month = end,
    products = nrow(results), built = sum(results$event == "BUILT"), reused = sum(results$event == "REUSED"),
    failed = sum(results$status == "FAILED"), elapsed_seconds = proc.time()[["elapsed"]] - started)
  write_prism_monthly_audit_report(summary, file.path(output_dir, "summary.csv"))
  gallery <- NA_character_
  if (make_maps && summary$status == "READY") {
    cards <- vapply(durations, function(d) paste0('<article><h2>SPI-', d,
      '</h2><a href="', end, '/', sprintf("%02dmonth", d), '/spi.png"><img src="', end, '/',
      sprintf("%02dmonth", d), '/spi.png" alt="SPI-', d, '"></a></article>'), character(1))
    gallery <- file.path(output_dir, "index.html")
    writeLines(c('<!doctype html><html lang="en"><meta charset="utf-8"><title>Monthly SPI pilots</title>',
      '<meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font-family:system-ui;max-width:1500px;margin:24px auto;padding:0 16px;background:#f1f4f4;color:#24363f}.maps{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}article{background:white;padding:10px;border:1px solid #ccd5da;border-radius:8px}img{width:100%}@media(max-width:850px){.maps{grid-template-columns:1fr}}</style>',
      paste0('<h1>Monthly SPI through ', end, '</h1>'),
      paste0('<p>Local pilot only. Gamma MLE with fixed ', policy$calibration_start, '-', policy$calibration_end,
        ' calibration and zero-mass correction. Gray cells failed support/fit checks; SPI is precipitation-only and does not measure evaporative demand or actual streamflow. Click maps for full resolution.</p><div class="maps">'),
      cards, '</div></html>'), gallery)
  }
  list(summary = summary, results = results, gallery = gallery)
}

# Conservative publication gate for SNODAS snow maps. It never changes raster
# values and does not itself publish products.

assess_snodas_swe_map_quality <- function(
    inputs, review,
    minimum_valid_fraction = 0.80,
    minimum_reference_overlap = 0.80) {
  if (!is.list(inputs) ||
      !all(c("date", "observed", "median_swe", "sample_years", "qc") %in%
           names(inputs)) ||
      !inherits(inputs$observed, "SpatRaster") ||
      !inherits(inputs$median_swe, "SpatRaster") ||
      !inherits(inputs$sample_years, "SpatRaster") ||
      !terra::compareGeom(inputs$observed, inputs$median_swe,
                          stopOnError = FALSE) ||
      !terra::compareGeom(inputs$observed, inputs$sample_years,
                          stopOnError = FALSE) ||
      !is.data.frame(review) || nrow(review) != 1L ||
      !all(c("high_swe_review_flag", "screened_excluded_cells") %in%
           names(review)) ||
      length(review$high_swe_review_flag) != 1L ||
      is.na(review$high_swe_review_flag) ||
      !is.logical(review$high_swe_review_flag) ||
      length(review$screened_excluded_cells) != 1L ||
      !is.numeric(review$screened_excluded_cells) ||
      !is.finite(review$screened_excluded_cells) ||
      review$screened_excluded_cells < 0) {
    stop("Invalid SNODAS map quality inputs.", call. = FALSE)
  }
  for (value in c(minimum_valid_fraction, minimum_reference_overlap)) {
    if (!is.numeric(value) || length(value) != 1L ||
        !is.finite(value) || value <= 0 || value > 1) {
      stop("SNODAS quality fractions must be in (0, 1].", call. = FALSE)
    }
  }
  observed <- terra::values(inputs$observed, mat = FALSE)
  reference <- terra::values(inputs$median_swe, mat = FALSE)
  samples <- terra::values(inputs$sample_years, mat = FALSE)
  valid <- is.finite(observed)
  overlap <- valid & is.finite(reference) & is.finite(samples) &
    samples >= 15
  valid_fraction <- mean(valid)
  overlap_fraction <- if (sum(valid)) sum(overlap) / sum(valid) else 0
  failures <- character()
  reviews <- character()
  if (!sum(valid)) failures <- c(failures, "no valid observed SWE cells")
  if (!sum(overlap)) {
    failures <- c(failures, "no cells with a valid 15-year reference")
  }
  if (valid_fraction < minimum_valid_fraction) {
    reviews <- c(reviews, "low observed coverage")
  }
  if (overlap_fraction < minimum_reference_overlap) {
    reviews <- c(reviews, "low reference overlap")
  }
  if (isTRUE(review$high_swe_review_flag[[1L]])) {
    reviews <- c(reviews, "SWE at or above 50 inches")
  }
  if (review$screened_excluded_cells[[1L]] > 0L) {
    reviews <- c(reviews, "paired SWE/depth cells excluded")
  }
  status <- if (length(failures)) "FAIL" else if (length(reviews)) {
    "REVIEW"
  } else "PASS"
  data.frame(
    date = as.character(snodas_date(inputs$date)),
    status = status,
    reasons = paste(c(failures, reviews), collapse = "; "),
    observed_valid_fraction = valid_fraction,
    reference_overlap_fraction = overlap_fraction,
    screened_excluded_cells = review$screened_excluded_cells[[1L]],
    high_swe_review_flag = review$high_swe_review_flag[[1L]],
    stringsAsFactors = FALSE
  )
}

require_snodas_swe_map_publishable <- function(gate) {
  if (!is.data.frame(gate) || nrow(gate) != 1L ||
      !all(c("status", "reasons") %in% names(gate)) ||
      !identical(gate$status[[1L]], "PASS")) {
    stop("SNODAS map publication is blocked: ",
         if (is.data.frame(gate) && nrow(gate) == 1L &&
             "reasons" %in% names(gate)) gate$reasons[[1L]] else
               "quality gate did not pass",
         call. = FALSE)
  }
  invisible(TRUE)
}

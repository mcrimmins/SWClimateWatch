# Display-mode and categorical-class helpers for public map products.

configured_map_product_scale <- function(
    product_id,
    config_path = getOption(
      "swc.map.product.config",
      file.path("config", "map-products.yml")
    )) {
  product_id <- as.character(product_id)
  if (length(product_id) != 1L || is.na(product_id) || !nzchar(product_id)) {
    return("continuous")
  }

  configured <- getOption("swc.map.product.scale_modes")
  if (!is.null(configured) && product_id %in% names(configured)) {
    return(match.arg(unname(configured[[product_id]]), c("continuous", "categorical")))
  }

  if (exists("read_map_product_config", mode = "function") && file.exists(config_path)) {
    products <- read_map_product_config(config_path)
    row <- match(product_id, products$id)
    if (!is.na(row)) return(products$scale[[row]])
  }
  "continuous"
}

format_map_class_value <- function(value) {
  ifelse(
    abs(value - round(value)) < 1e-8,
    format(round(value), trim = TRUE, scientific = FALSE),
    format(round(value, 1), trim = TRUE, scientific = FALSE)
  )
}

map_interval_labels <- function(boundaries, suffix = "") {
  values <- format_map_class_value(boundaries)
  count <- length(boundaries) - 1L
  labels <- character(count)
  labels[[1L]] <- paste0("<=", values[[2L]], suffix)
  if (count > 2L) {
    for (index in 2:(count - 1L)) {
      labels[[index]] <- paste0(
        values[[index]], "-", values[[index + 1L]], suffix
      )
    }
  }
  if (count > 1L) labels[[count]] <- paste0(">", values[[count]], suffix)
  labels
}

map_product_categorical_classes <- function(
    product_id,
    breaks,
    limits) {
  product_id <- if (is.null(product_id)) "" else as.character(product_id)
  limits <- as.numeric(limits)
  if (length(limits) != 2L || anyNA(limits) || limits[[1L]] >= limits[[2L]]) {
    stop("Categorical map scales require two increasing finite limits.", call. = FALSE)
  }

  if (grepl("percentile", product_id) && !grepl("change", product_id)) {
    boundaries <- c(0, 2, 10, 33, 67, 90, 98, 100)
    labels <- c(
      "<=2\nnear-record low",
      "2-10\nmuch below",
      "10-33\nbelow",
      "33-67\nnear normal",
      "67-90\nabove",
      "90-98\nmuch above",
      ">98\nnear-record high"
    )
  } else if (grepl("percent_normal", product_id)) {
    boundaries <- c(0, 50, 75, 90, 110, 125, 150, 200)
    labels <- c("<=50%", "50-75%", "75-90%", "90-110%", "110-125%", "125-150%", ">150%")
  } else if (grepl("percentile_change", product_id)) {
    boundaries <- c(-100, -50, -25, -10, 10, 25, 50, 100)
    labels <- c("<=-50", "-50--25", "-25--10", "-10-10", "10-25", "25-50", ">50")
  } else if (grepl("departure_daily$", product_id)) {
    boundaries <- c(-30, -10, -5, 5, 10, 30)
    labels <- c("<=-10", "-10--5", "-5-5", "5-10", ">10")
  } else if (grepl("departure_30day$", product_id)) {
    boundaries <- c(-15, -5, -2, 2, 5, 15)
    labels <- c("<=-5", "-5--2", "-2-2", "2-5", ">5")
  } else if (product_id %in% c(
    "mint_first_freeze_departure",
    "mint_last_freeze_departure",
    "mint_freeze_free_departure"
  )) {
    boundaries <- c(-60, -30, -14, 14, 30, 60)
    labels <- c("<=-30", "-30--14", "-14-14", "14-30", ">30")
  } else if (product_id == "mint_freeze_anomaly_30day") {
    boundaries <- c(-10, -5, -2, 2, 5, 10)
    labels <- c("<=-5", "-5--2", "-2-2", "2-5", ">5")
  } else if (product_id == "mint_first_freeze_date") {
    boundaries <- c(1, 32, 93, 154, 213, 365)
    labels <- c("August", "Sep-Oct", "Nov-Dec", "Jan-Feb", "Mar-Jul")
  } else if (product_id == "mint_last_freeze_date") {
    boundaries <- c(1, 93, 154, 213, 274, 365)
    labels <- c("By Oct", "Nov-Dec", "Jan-Feb", "Mar-Apr", "May-Jul")
  } else {
    boundaries <- sort(unique(c(limits, as.numeric(breaks))))
    boundaries <- boundaries[boundaries >= limits[[1L]] & boundaries <= limits[[2L]]]
    if (length(boundaries) < 2L) boundaries <- limits
    labels <- map_interval_labels(boundaries)
  }

  list(breaks = boundaries, labels = labels)
}

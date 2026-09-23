# Generate the map-product pages and Quarto navigation from one configuration.

read_map_product_config <- function(path = file.path("config", "map-products.yml")) {
  if (!file.exists(path)) stop("Map-product configuration does not exist: ", path, call. = FALSE)
  config <- yaml::read_yaml(path)
  if (!identical(as.integer(config$version), 1L)) {
    stop("Unsupported map-product configuration version.", call. = FALSE)
  }
  if (is.null(config$products) || length(config$products) == 0L || is.null(names(config$products))) {
    stop("Map-product configuration must contain named products.", call. = FALSE)
  }
  defaults <- config$defaults %||% list(enabled = TRUE, scale = "continuous")
  ids <- names(config$products)
  if (any(!grepl("^[a-z0-9_]+$", ids))) {
    stop("Map-product IDs may contain only lowercase letters, numbers, and underscores.", call. = FALSE)
  }

  rows <- lapply(seq_along(config$products), function(index) {
    product <- utils::modifyList(defaults, config$products[[index]])
    required <- c("enabled", "scale", "section", "group", "label", "image", "description")
    missing <- required[!vapply(required, function(field) {
      !is.null(product[[field]]) && length(product[[field]]) == 1L && !is.na(product[[field]])
    }, logical(1))]
    if (length(missing) > 0L) {
      stop("Map product `", ids[[index]], "` is missing: ", paste(missing, collapse = ", "), call. = FALSE)
    }
    if (!is.logical(product$enabled)) {
      stop("Map product `", ids[[index]], "` has a non-logical `enabled` value.", call. = FALSE)
    }
    scale <- tolower(as.character(product$scale))
    if (!scale %in% c("continuous", "categorical")) {
      stop("Map product `", ids[[index]], "` must use `continuous` or `categorical` scale.", call. = FALSE)
    }
    description <- trimws(as.character(product$description))
    if (!nzchar(description)) {
      stop("Map product `", ids[[index]], "` needs a non-empty `description`.", call. = FALSE)
    }
    data.frame(
      id = ids[[index]],
      enabled = product$enabled,
      scale = scale,
      section = as.character(product$section),
      group = as.character(product$group),
      label = as.character(product$label),
      image = gsub("\\\\", "/", as.character(product$image)),
      description = description,
      order = index,
      stringsAsFactors = FALSE
    )
  })
  products <- do.call(rbind, rows)
  if (anyDuplicated(products$image)) {
    stop("Every map product must reference a unique image.", call. = FALSE)
  }
  products
}

`%||%` <- function(x, y) if (is.null(x)) y else x

read_map_dashboard_config <- function(
    path = file.path("config", "map-products.yml"),
    products = read_map_product_config(path)) {
  config <- yaml::read_yaml(path)
  ids <- unlist(config$dashboard$products, use.names = FALSE)
  ids <- as.character(ids)
  if (length(ids) < 4L || length(ids) > 6L) {
    stop("The homepage dashboard must contain four to six product IDs.", call. = FALSE)
  }
  if (any(!nzchar(ids)) || anyDuplicated(ids)) {
    stop("Homepage dashboard product IDs must be non-empty and unique.", call. = FALSE)
  }
  missing <- setdiff(ids, products$id)
  if (length(missing) > 0L) {
    stop(
      "Unknown homepage dashboard product ID(s): ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  dashboard <- products[match(ids, products$id), , drop = FALSE]
  disabled <- dashboard$id[!dashboard$enabled]
  if (length(disabled) > 0L) {
    stop(
      "Homepage dashboard products must be enabled: ",
      paste(disabled, collapse = ", "),
      call. = FALSE
    )
  }
  dashboard$dashboard_order <- seq_len(nrow(dashboard))
  rownames(dashboard) <- NULL
  dashboard
}

map_dashboard_date_line <- function(expected_data_dates = NULL) {
  if (is.null(expected_data_dates) || length(expected_data_dates) == 0L) {
    return("Latest available PRISM data")
  }
  dates <- suppressWarnings(as.Date(as.character(expected_data_dates)))
  keep <- !is.na(dates)
  dates <- dates[keep]
  labels <- names(expected_data_dates)[keep]
  pretty_date <- function(date) format(date, "%B %d, %Y")
  if (length(dates) == 0L) return("Latest available PRISM data")
  if (length(unique(dates)) == 1L) {
    return(paste0("Data through ", pretty_date(dates[[1L]])))
  }
  paste0(
    labels, " through ", vapply(dates, pretty_date, character(1)),
    collapse = " · "
  )
}

map_dashboard_page_text <- function(dashboard, expected_data_dates = NULL) {
  lines <- c(
    "---",
    'title: "Current Conditions"',
    'subtitle: "Southwest Climate Watch"',
    "page-layout: full",
    "toc: false",
    "body-classes: dashboard-page",
    "---",
    "",
    "::: {.dashboard-intro}",
    "Key temperature and precipitation indicators for Arizona and New Mexico.",
    "",
    paste0("**", map_dashboard_date_line(expected_data_dates), "** · Reference period: 1991–2020"),
    "",
    "Explore all maps from Map Browser in the navigation menu.",
    ":::",
    "",
    "::: {.dashboard-map-grid}"
  )
  for (index in seq_len(nrow(dashboard))) {
    product <- dashboard[index, , drop = FALSE]
    image <- paste0("maps/generated/", product$image)
    page <- paste0("pages/products/", product$id, ".qmd")
    alt <- paste0("Map showing ", tolower(product$label), " across Arizona and New Mexico")
    loading <- if (index <= 2L) "" else ' loading="lazy"'
    lines <- c(
      lines,
      "::: {.dashboard-map-card}",
      paste0("[![](", image, '){fig-alt="', alt, '"', loading, "}](", page, ")"),
      "",
      "::: {.dashboard-card-actions}",
      paste0("[View details](", page, "){.btn .btn-sm .btn-outline-primary}"),
      paste0("[Full-resolution PNG](", image, "){.dashboard-full-resolution}"),
      ":::",
      ":::",
      ""
    )
  }
  c(
    lines,
    ":::",
    "",
    "::: {.dashboard-note}",
    "Percentile rank compares current conditions with the same time of year in 1991–2020. Low precipitation ranks indicate drier conditions; high temperature ranks indicate warmer conditions. A high dry-spell rank means the ongoing dry spell is unusually long.",
    ":::",
    "",
    "::: {.institutional-branding .dashboard-branding}",
    "![](assets/branding/ua-csap-climas-logos-horizontal.png){fig-alt=\"Logos for CLIMAS, the Climate Science Applications Program, and University of Arizona Cooperative Extension\"}",
    "",
    "::: {.dashboard-branding-links}",
    "[Climate Assessment for the Southwest](https://www.climas.arizona.edu/) · [Climate Science Applications Program](https://cales.arizona.edu/climate/) · [University of Arizona Cooperative Extension](https://extension.arizona.edu/topics/climate)",
    ":::",
    "",
    "::: {.dashboard-contact}",
    "Mike Crimmins · [crimmins@arizona.edu](mailto:crimmins@arizona.edu)",
    ":::",
    ":::"
  )
}

map_product_is_seasonal <- function(id) {
  grepl("^mint_(first_freeze|last_freeze|freeze_free)", as.character(id))
}

map_product_png_info <- function(path) {
  result <- list(
    readable = FALSE,
    width = NA_integer_,
    height = NA_integer_,
    bytes = NA_real_,
    modified_utc = NA_character_,
    md5 = NA_character_
  )
  if (!file.exists(path)) return(result)
  file_details <- file.info(path)
  result$bytes <- unname(file_details$size[[1L]])
  result$modified_utc <- format(
    as.POSIXct(file_details$mtime[[1L]], tz = "UTC"),
    "%Y-%m-%d %H:%M:%S UTC",
    tz = "UTC"
  )
  result$md5 <- unname(tools::md5sum(path))
  image_details <- tryCatch(
    magick::image_info(magick::image_read(path))[1L, , drop = FALSE],
    error = function(error) NULL
  )
  if (!is.null(image_details)) {
    result$readable <- TRUE
    result$width <- as.integer(image_details$width[[1L]])
    result$height <- as.integer(image_details$height[[1L]])
  }
  result
}

map_product_dated_companion <- function(path, latest_md5 = NA_character_) {
  result <- list(path = NA_character_, date = as.Date(NA_character_))
  filename <- basename(path)
  if (!grepl("-latest\\.png$", filename) || !file.exists(path)) return(result)
  prefix <- sub("latest\\.png$", "", filename)
  candidates <- list.files(dirname(path), pattern = "\\.png$", full.names = TRUE)
  candidate_names <- basename(candidates)
  suffix <- substring(candidate_names, nchar(prefix) + 1L)
  date_text <- substring(suffix, 1L, 10L)
  valid <- startsWith(candidate_names, prefix) &
    suffix == paste0(date_text, ".png") &
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.png$", suffix)
  candidates <- candidates[valid]
  dates <- suppressWarnings(as.Date(date_text[valid]))
  keep <- !is.na(dates)
  candidates <- candidates[keep]
  dates <- dates[keep]
  if (length(candidates) == 0L) return(result)

  latest_size <- file.info(path)$size[[1L]]
  same_size <- file.info(candidates)$size == latest_size
  candidates <- candidates[same_size]
  dates <- dates[same_size]
  if (length(candidates) == 0L) return(result)
  if (is.na(latest_md5)) latest_md5 <- unname(tools::md5sum(path))
  same_content <- unname(tools::md5sum(candidates)) == latest_md5
  candidates <- candidates[same_content]
  dates <- dates[same_content]
  if (length(candidates) == 0L) return(result)
  selected <- which.max(dates)
  list(path = candidates[[selected]], date = dates[[selected]])
}

map_product_expected_data_dates <- function(products = read_map_product_config()) {
  if (!exists("latest_common_prism_date", mode = "function")) {
    stop(
      "`latest_common_prism_date()` must be available to determine expected map dates.",
      call. = FALSE
    )
  }
  enabled_sections <- unique(products$section[products$enabled])
  dates <- character()
  if ("Temperature" %in% enabled_sections) {
    dates[["Temperature"]] <- format(latest_common_prism_date(c("maxt", "mint")))
  }
  if ("Precipitation" %in% enabled_sections) {
    dates[["Precipitation"]] <- format(latest_common_prism_date("pcpn"))
  }
  if (length(dates) == 0L) NULL else dates
}

validate_map_product_publication <- function(
    products = read_map_product_config(),
    site_dir = "site",
    expected_data_dates = NULL,
    expected_dimensions = c(width = 1998L, height = 1533L),
    minimum_image_bytes = 10000,
    require_rendered = FALSE,
    report_path = file.path("data", "diagnostics", "map-product-status.csv"),
    fail = TRUE) {
  if (length(expected_dimensions) != 2L || any(!is.finite(expected_dimensions))) {
    stop("`expected_dimensions` must contain a finite width and height.", call. = FALSE)
  }
  expected_dimensions <- as.integer(expected_dimensions)
  expected_width <- unname(expected_dimensions[[1L]])
  expected_height <- unname(expected_dimensions[[2L]])
  if (length(minimum_image_bytes) != 1L || minimum_image_bytes < 1) {
    stop("`minimum_image_bytes` must be a positive number.", call. = FALSE)
  }

  quarto_path <- file.path(site_dir, "_quarto.yml")
  navigation <- if (file.exists(quarto_path)) readLines(quarto_path, warn = FALSE) else character()
  expected_dates <- rep(as.Date(NA_character_), nrow(products))
  if (!is.null(expected_data_dates)) {
    if (is.null(names(expected_data_dates))) {
      stop("`expected_data_dates` must be named by catalog section.", call. = FALSE)
    }
    for (index in seq_len(nrow(products))) {
      section <- products$section[[index]]
      if (section %in% names(expected_data_dates)) {
        expected_dates[[index]] <- as.Date(expected_data_dates[[section]])
      }
    }
  }

  rows <- lapply(seq_len(nrow(products)), function(index) {
    product <- products[index, , drop = FALSE]
    image_path <- file.path(site_dir, "maps", "generated", product$image)
    page_path <- map_product_page_path(product$id, site_dir)
    rendered_path <- file.path(
      site_dir, "_site", "pages", "products", paste0(product$id, ".html")
    )
    image <- map_product_png_info(image_path)
    companion <- map_product_dated_companion(image_path, image$md5)
    image_reference <- paste0("../../maps/generated/", product$image)
    page_text <- if (file.exists(page_path)) readLines(page_path, warn = FALSE) else character()
    rendered_text <- if (file.exists(rendered_path)) {
      readLines(rendered_path, warn = FALSE)
    } else {
      character()
    }
    page_image_link <- any(grepl(
      paste0("![](", image_reference, ")"), page_text, fixed = TRUE
    ))
    page_download_link <- any(grepl(
      paste0("[Open full-resolution PNG](", image_reference, ")"),
      page_text,
      fixed = TRUE
    ))
    navigation_reference <- paste0("pages/products/", product$id, ".qmd")
    navigation_link <- any(grepl(navigation_reference, navigation, fixed = TRUE))
    rendered_image_link <- any(grepl(image_reference, rendered_text, fixed = TRUE))
    rendered_download_link <- any(grepl("Open full-resolution PNG", rendered_text, fixed = TRUE))
    seasonal <- map_product_is_seasonal(product$id)
    expected_date <- expected_dates[[index]]
    freshness_checked <- isTRUE(product$enabled) && !seasonal && !is.na(expected_date)
    freshness_ok <- !freshness_checked || (
      !is.na(companion$date) && companion$date == expected_date
    )

    problems <- character()
    if (isTRUE(product$enabled)) {
      if (!file.exists(image_path)) problems <- c(problems, "map image is missing")
      if (file.exists(image_path) && !image$readable) problems <- c(problems, "map image is not a readable PNG")
      if (!is.na(image$bytes) && image$bytes < minimum_image_bytes) {
        problems <- c(problems, "map image is unexpectedly small")
      }
      if (image$readable && (
        image$width != expected_width || image$height != expected_height
      )) {
        problems <- c(problems, sprintf(
          "map dimensions are %sx%s instead of %sx%s",
          image$width, image$height, expected_width, expected_height
        ))
      }
      if (is.na(companion$date)) problems <- c(problems, "matching dated map is missing")
      if (!file.exists(page_path)) problems <- c(problems, "source page is missing")
      if (file.exists(page_path) && !page_image_link) problems <- c(problems, "source page map link is incorrect")
      if (file.exists(page_path) && !page_download_link) problems <- c(problems, "full-resolution link is incorrect")
      if (!navigation_link) problems <- c(problems, "navigation link is missing")
      if (freshness_checked && !freshness_ok) {
        problems <- c(problems, sprintf(
          "map data date is %s instead of %s",
          if (is.na(companion$date)) "unknown" else format(companion$date),
          format(expected_date)
        ))
      }
      if (isTRUE(require_rendered)) {
        if (!file.exists(rendered_path)) problems <- c(problems, "rendered page is missing")
        if (file.exists(rendered_path) && !rendered_image_link) {
          problems <- c(problems, "rendered page map link is incorrect")
        }
        if (file.exists(rendered_path) && !rendered_download_link) {
          problems <- c(problems, "rendered full-resolution link is missing")
        }
      }
    } else {
      if (file.exists(page_path)) problems <- c(problems, "disabled source page is still present")
      if (navigation_link) problems <- c(problems, "disabled product remains in navigation")
      if (isTRUE(require_rendered) && file.exists(rendered_path)) {
        problems <- c(problems, "disabled rendered page is still present")
      }
    }

    data.frame(
      id = product$id,
      enabled = product$enabled,
      section = product$section,
      group = product$group,
      label = product$label,
      scale = product$scale,
      validation_status = if (length(problems) == 0L) "PASS" else "FAIL",
      problems = paste(problems, collapse = "; "),
      actual_data_date = if (is.na(companion$date)) NA_character_ else format(companion$date),
      expected_data_date = if (is.na(expected_date)) NA_character_ else format(expected_date),
      freshness_policy = if (seasonal) "seasonal-retention" else if (freshness_checked) "current" else "not-checked",
      image_bytes = image$bytes,
      image_width = image$width,
      image_height = image$height,
      image_modified_utc = image$modified_utc,
      image_md5 = image$md5,
      image_path = gsub("\\\\", "/", image_path),
      page_path = gsub("\\\\", "/", page_path),
      rendered_path = gsub("\\\\", "/", rendered_path),
      stringsAsFactors = FALSE
    )
  })
  status <- do.call(rbind, rows)
  summary <- data.frame(
    configured = nrow(status),
    enabled = sum(status$enabled),
    passed = sum(status$validation_status == "PASS"),
    failed = sum(status$validation_status == "FAIL"),
    rendered_pages_checked = isTRUE(require_rendered),
    stringsAsFactors = FALSE
  )
  if (!is.null(report_path)) {
    dir.create(dirname(report_path), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(status, report_path, row.names = FALSE, na = "")
  }
  result <- list(status = status, summary = summary, report_path = report_path)
  class(result) <- "map_product_validation"
  failed <- status[status$validation_status == "FAIL", , drop = FALSE]
  if (isTRUE(fail) && nrow(failed) > 0L) {
    details <- paste0(failed$id, ": ", failed$problems)
    stop(
      "Map-product validation failed for ", nrow(failed), " product(s): ",
      paste(details, collapse = " | "),
      call. = FALSE
    )
  }
  result
}

print.map_product_validation <- function(x, ...) {
  print(x$summary, row.names = FALSE)
  if (!is.null(x$report_path)) cat("Status report: ", x$report_path, "\n", sep = "")
  invisible(x)
}

map_product_page_path <- function(id, site_dir = "site") {
  file.path(site_dir, "pages", "products", paste0(id, ".qmd"))
}

map_product_page_text <- function(product) {
  description <- product$description
  image <- paste0("../../maps/generated/", product$image)
  alt <- paste0("Map showing ", tolower(product$label), " across Arizona and New Mexico")
  c(
    "---",
    paste0('title: "', gsub('"', '\\"', product$label), '"'),
    paste0('description-meta: "', gsub('"', '\\"', description), '"'),
    "body-classes: product-page",
    "toc: false",
    "page-layout: full",
    "---",
    "",
    "::: {.product-map-card}",
    paste0("![](", image, '){fig-alt="', alt, '"}'),
    ":::",
    "",
    "::: {.product-interpretation}",
    description,
    ":::",
    "",
    "::: {.product-actions}",
    paste0("[Open full-resolution PNG](", image, "){.btn .btn-outline-primary}"),
    ":::"
  )
}

map_product_navigation_lines <- function(products) {
  enabled <- products[products$enabled, , drop = FALSE]
  lines <- c(
    "      # BEGIN GENERATED MAP BROWSER",
    "      - section: Map Browser",
    "        contents:"
  )
  for (section in unique(enabled$section)) {
    section_products <- enabled[enabled$section == section, , drop = FALSE]
    lines <- c(lines, paste0("          - section: ", section), "            contents:")
    for (group in unique(section_products$group)) {
      group_products <- section_products[section_products$group == group, , drop = FALSE]
      lines <- c(lines, paste0("              - section: ", group), "                contents:")
      for (index in seq_len(nrow(group_products))) {
        product <- group_products[index, , drop = FALSE]
        lines <- c(
          lines,
          paste0("                  - href: pages/products/", product$id, ".qmd"),
          paste0("                    text: ", product$label)
        )
      }
    }
  }
  c(lines, "      # END GENERATED MAP BROWSER")
}

update_map_product_navigation <- function(
    products,
    quarto_path = file.path("site", "_quarto.yml")) {
  text <- readLines(quarto_path, warn = FALSE)
  start <- grep("^      # BEGIN GENERATED MAP BROWSER$", text)
  end <- grep("^      # END GENERATED MAP BROWSER$", text)
  if (length(start) != 1L || length(end) != 1L || start >= end) {
    stop("Quarto configuration is missing valid generated-navigation markers.", call. = FALSE)
  }
  replacement <- map_product_navigation_lines(products)
  updated <- c(text[seq_len(start - 1L)], replacement, text[(end + 1L):length(text)])
  writeLines(updated, quarto_path, useBytes = TRUE)
  invisible(quarto_path)
}

build_map_product_site <- function(
    config_path = file.path("config", "map-products.yml"),
    site_dir = "site",
    require_images = TRUE,
    expected_data_dates = NULL,
    expected_dimensions = c(width = 1998L, height = 1533L),
    minimum_image_bytes = 10000,
    status_path = file.path("data", "diagnostics", "map-product-status.csv")) {
  products <- read_map_product_config(config_path)
  enabled <- products[products$enabled, , drop = FALSE]
  dashboard <- read_map_dashboard_config(config_path, products)
  if (isTRUE(require_images)) {
    image_paths <- file.path(site_dir, "maps", "generated", enabled$image)
    missing <- !file.exists(image_paths)
    if (any(missing)) {
      stop("Enabled map image is missing: ", image_paths[which(missing)[[1L]]], call. = FALSE)
    }
  }

  pages_dir <- file.path(site_dir, "pages", "products")
  dir.create(pages_dir, recursive = TRUE, showWarnings = FALSE)
  existing <- list.files(pages_dir, pattern = "\\.qmd$", full.names = TRUE)
  expected <- vapply(enabled$id, map_product_page_path, character(1), site_dir = site_dir)
  stale <- setdiff(existing, expected)
  if (length(stale) > 0L) unlink(stale)
  for (index in seq_len(nrow(enabled))) {
    writeLines(
      map_product_page_text(enabled[index, , drop = FALSE]),
      map_product_page_path(enabled$id[[index]], site_dir),
      useBytes = TRUE
    )
  }
  writeLines(
    map_dashboard_page_text(dashboard, expected_data_dates),
    file.path(site_dir, "index.qmd"),
    useBytes = TRUE
  )
  update_map_product_navigation(
    products,
    quarto_path = file.path(site_dir, "_quarto.yml")
  )
  if (isTRUE(require_images)) {
    validate_map_product_publication(
      products = products,
      site_dir = site_dir,
      expected_data_dates = expected_data_dates,
      expected_dimensions = expected_dimensions,
      minimum_image_bytes = minimum_image_bytes,
      report_path = status_path
    )
  }
  invisible(products)
}

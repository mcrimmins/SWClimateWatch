# Publication checks for the fixed Historic Years archive. This reads only
# existing source and rendered files; it never builds maps or downloads data.

validate_prism_archive_publication <- function(
    site_dir = "site",
    expected_years = 1982:2025,
    products = prism_archive_product_specs()$id,
    roni = read_prism_archive_roni(),
    expected_dimensions = c(width = 1998L, height = 1533L),
    legacy_dimensions = list(
      `1998` = c(width = 2070L, height = 1472L),
      `2011` = c(width = 2070L, height = 1472L)
    ),
    minimum_image_bytes = 10000,
    require_rendered = FALSE,
    report_path = file.path("data", "diagnostics", "archive-publication-status.csv"),
    fail = TRUE) {
  expected_years <- as.integer(expected_years)
  if (!length(expected_years) || anyNA(expected_years) ||
      anyDuplicated(expected_years) || any(!expected_years %in% roni$water_year)) {
    stop("Expected archive years must be unique and present in the RONI snapshot.",
         call. = FALSE)
  }
  if (!length(products) || anyNA(products) || anyDuplicated(products) ||
      any(!products %in% prism_archive_product_specs()$id)) {
    stop("Archive products must be unique known product IDs.", call. = FALSE)
  }
  if (length(expected_dimensions) != 2L || anyNA(expected_dimensions) ||
      any(expected_dimensions < 1) || !is.numeric(minimum_image_bytes) ||
      length(minimum_image_bytes) != 1L || is.na(minimum_image_bytes) ||
      minimum_image_bytes < 1) {
    stop("Specify positive image dimensions and minimum bytes.", call. = FALSE)
  }
  if (!is.list(legacy_dimensions) ||
      any(!vapply(legacy_dimensions, function(size) {
        is.numeric(size) && length(size) == 2L && !anyNA(size) && all(size > 0)
      }, logical(1)))) {
    stop("Legacy dimensions must be named positive width-height pairs.", call. = FALSE)
  }
  if (isTRUE(require_rendered) && !requireNamespace("xml2", quietly = TRUE)) {
    stop("The xml2 package is required to inspect rendered archive pages.", call. = FALSE)
  }
  navigation_path <- file.path(site_dir, "_quarto.yml")
  navigation <- if (file.exists(navigation_path)) {
    trimws(readLines(navigation_path, warn = FALSE))
  } else character()
  records <- vector("list", length(expected_years) * length(products))
  index <- 0L

  for (year in expected_years) {
    page_path <- file.path(site_dir, "pages", "archive", sprintf("wy%04d.qmd", year))
    rendered_path <- file.path(site_dir, "_site", "pages", "archive",
                               sprintf("wy%04d.html", year))
    page_lines <- if (file.exists(page_path)) {
      readLines(page_path, warn = FALSE)
    } else character()
    rendered <- if (isTRUE(require_rendered) && file.exists(rendered_path)) {
      tryCatch(xml2::read_html(rendered_path), error = function(error) NULL)
    } else NULL
    rendered_images <- if (!is.null(rendered)) {
      xml2::xml_attr(xml2::xml_find_all(rendered, "//img[@src]"), "src")
    } else character()
    rendered_anchors <- if (!is.null(rendered)) {
      xml2::xml_find_all(rendered, "//a[@href]")
    } else NULL
    rendered_links <- if (!is.null(rendered_anchors)) {
      xml2::xml_attr(rendered_anchors, "href")
    } else character()
    rendered_labels <- if (!is.null(rendered_anchors)) {
      xml2::xml_text(rendered_anchors)
    } else character()
    navigation_ref <- sprintf("- href: pages/archive/wy%04d.qmd", year)
    year_problems <- character()
    if (!file.exists(page_path)) year_problems <- c(year_problems, "source page is missing")
    if (sum(navigation == navigation_ref) != 1L) {
      year_problems <- c(year_problems, "navigation entry is missing or duplicated")
    }
    roni_value <- roni$djf_roni[match(year, roni$water_year)]
    badge <- sprintf("RONI %+.1f", roni_value)
    badge_class <- prism_archive_roni_category(roni_value)$class
    if (file.exists(page_path) &&
        (!any(grepl(badge, page_lines, fixed = TRUE)) ||
         !any(grepl(badge_class, page_lines, fixed = TRUE)))) {
      year_problems <- c(year_problems, "RONI badge disagrees with the dated snapshot")
    }
    if (isTRUE(require_rendered)) {
      if (!file.exists(rendered_path)) {
        year_problems <- c(year_problems, "rendered page is missing")
      } else if (is.null(rendered)) {
        year_problems <- c(year_problems, "rendered page is not readable HTML")
      }
    }

    for (product in products) {
      relative_image <- sprintf(
        "prism/seasonal-archive/wy%04d/%s.png", year, product
      )
      image_ref <- paste0("../../maps/generated/", relative_image)
      image_path <- file.path(site_dir, "maps", "generated", relative_image)
      rendered_image_path <- file.path(site_dir, "_site", "maps", "generated",
                                       relative_image)
      image <- map_product_png_info(image_path)
      legacy_size <- legacy_dimensions[[as.character(year)]]
      legacy_layout <- image$readable && !is.null(legacy_size) &&
        identical(c(image$width, image$height), as.integer(legacy_size))
      problems <- year_problems
      if (!file.exists(image_path)) {
        problems <- c(problems, "source PNG is missing")
      } else {
        if (!image$readable) problems <- c(problems, "source PNG is unreadable")
        if (!is.na(image$bytes) && image$bytes < minimum_image_bytes) {
          problems <- c(problems, "source PNG is unexpectedly small")
        }
        if (image$readable && !legacy_layout &&
            !identical(c(image$width, image$height), as.integer(expected_dimensions))) {
          problems <- c(problems, "source PNG dimensions are incorrect")
        }
      }
      source_image_line <- grepl(paste0("](", image_ref, ")"), page_lines, fixed = TRUE) &
        startsWith(trimws(page_lines), "![")
      source_download_line <- grepl(
        paste0("[Open full-resolution PNG](", image_ref, ")"),
        page_lines, fixed = TRUE
      )
      if (sum(source_image_line) != 1L) {
        problems <- c(problems, "source page image link is missing or duplicated")
      }
      if (sum(source_download_line) != 1L) {
        problems <- c(problems, "source page download link is missing or duplicated")
      }
      if (isTRUE(require_rendered)) {
        if (file.exists(rendered_path) && !is.null(rendered)) {
          if (sum(rendered_images == image_ref) != 1L) {
            problems <- c(problems, "rendered page image link is missing or duplicated")
          }
          download <- rendered_links == image_ref &
            grepl("Open full-resolution PNG", rendered_labels, fixed = TRUE)
          if (sum(download) != 1L) {
            problems <- c(problems, "rendered page download link is missing or duplicated")
          }
        }
        if (!file.exists(rendered_image_path)) {
          problems <- c(problems, "rendered PNG is missing")
        } else if (image$readable &&
                   !identical(unname(tools::md5sum(rendered_image_path)), image$md5)) {
          problems <- c(problems, "rendered PNG differs from source")
        }
      }
      index <- index + 1L
      records[[index]] <- data.frame(
        water_year = year, product = product,
        validation_status = if (length(problems)) "FAIL" else "PASS",
        problems = paste(unique(problems), collapse = "; "),
        image_bytes = image$bytes, image_width = image$width,
        image_height = image$height, legacy_layout = legacy_layout,
        image_path = gsub("\\", "/", image_path, fixed = TRUE),
        page_path = gsub("\\", "/", page_path, fixed = TRUE),
        rendered_path = gsub("\\", "/", rendered_path, fixed = TRUE),
        stringsAsFactors = FALSE
      )
    }
  }
  status <- do.call(rbind, records)
  summary <- data.frame(
    years = length(expected_years), maps = nrow(status),
    passed = sum(status$validation_status == "PASS"),
    failed = sum(status$validation_status == "FAIL"),
    legacy_layout_maps = sum(status$legacy_layout),
    rendered_checked = isTRUE(require_rendered)
  )
  if (!is.null(report_path)) {
    dir.create(dirname(report_path), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(status, report_path, row.names = FALSE, na = "")
  }
  result <- list(status = status, summary = summary, report_path = report_path)
  class(result) <- "prism_archive_validation"
  failed <- status[status$validation_status == "FAIL", , drop = FALSE]
  if (isTRUE(fail) && nrow(failed)) {
    details <- paste0("WY", failed$water_year, " ", failed$product, ": ", failed$problems)
    stop("Historic Years validation failed for ", nrow(failed), " map(s): ",
         paste(head(details, 8L), collapse = " | "),
         if (length(details) > 8L) " | ...", call. = FALSE)
  }
  result
}

print.prism_archive_validation <- function(x, ...) {
  print(x$summary, row.names = FALSE)
  if (!is.null(x$report_path)) cat("Status report: ", x$report_path, "\n", sep = "")
  invisible(x)
}

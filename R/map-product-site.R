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

map_product_early_water_year_three_day <- function(products, expected_data_dates = NULL) {
  unavailable <- rep(FALSE, nrow(products))
  if (is.null(expected_data_dates) ||
      !"Precipitation" %in% names(expected_data_dates)) return(unavailable)
  date <- as.Date(expected_data_dates[["Precipitation"]])
  if (length(date) != 1L || is.na(date) ||
      !format(date, "%m-%d") %in% c("10-01", "10-02")) return(unavailable)
  unavailable <- products$enabled & products$id %in% c(
    "pcpn_water_year_max_03day",
    "pcpn_water_year_max_percentile_03day",
    "pcpn_water_year_concentration_03day"
  )
  unavailable
}

map_product_early_water_year_three_day_page <- function(product, date) {
  first_date <- as.Date(sprintf("%s-10-03", format(as.Date(date), "%Y")))
  c(
    "---",
    paste0('title: "', gsub('"', '\\"', product$label), '"'),
    'description-meta: "A complete three-day water-year period is not yet available."',
    "body-classes: product-page",
    "toc: false",
    "page-layout: full",
    "---",
    "",
    "::: {.product-interpretation}",
    "**Not yet available.** This water-year map requires three complete days of precipitation, starting October 1.",
    paste0("PRISM data currently extend through ", format(as.Date(date)),
           "; the first eligible period ends ", format(first_date),
           ". The map will appear here automatically when those data arrive."),
    ":::"
  )
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
  snow <- config$dashboard$seasonal_snow %||% list(enabled = FALSE)
  if(isTRUE(snow$enabled) && (!identical(snow$replace,"pcpn_current_dry_spell_percentile") ||
      !snow$replace %in% dashboard$id || length(snow$minimum_reference_cells)!=1L ||
      !is.numeric(snow$minimum_reference_cells) || !is.finite(snow$minimum_reference_cells) ||
      snow$minimum_reference_cells<1 || snow$minimum_reference_cells!=floor(snow$minimum_reference_cells) ||
      length(snow$maximum_age_days)!=1L || !is.numeric(snow$maximum_age_days) ||
      !is.finite(snow$maximum_age_days) || snow$maximum_age_days<0 || snow$maximum_age_days>7 ||
      snow$maximum_age_days!=floor(snow$maximum_age_days)))
    stop("Invalid seasonal snow dashboard settings.",call.=FALSE)
  attr(dashboard,"seasonal_snow") <- snow
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

map_dashboard_snow_selection <- function(site_dir="site",today=Sys.Date(),
    minimum_reference_cells=1000L,maximum_age_days=3L) {
  unavailable<-function(reason) list(available=FALSE,reason=reason)
  if(!as.integer(format(today,"%m")) %in% c(10:12,1:5))
    return(unavailable("Outside the October-May snow display season."))
  tryCatch({
    root<-dirname(site_dir)
    publication_path<-file.path(root,"data","diagnostics","snodas-current-site","publication.csv")
    if(!file.exists(publication_path)) return(unavailable("No verified snow publication."))
    publication<-utils::read.csv(publication_path)
    if(nrow(publication)!=1L || !all(c("date","water_year","percent_md5","page_md5") %in% names(publication)))
      return(unavailable("No verified snow publication."))
    date<-as.Date(publication$date)
    wy<-function(d) as.integer(format(d,"%Y"))+as.integer(format(d,"%m")>="10")
    if(is.na(date) || date>today || today-date>maximum_age_days || wy(date)!=wy(today) || publication$water_year!=wy(today))
      return(unavailable("Snow publication is stale or belongs to another season."))
    image<-file.path(site_dir,"maps","generated","snodas","current","swe-percent-median.png")
    page<-file.path(site_dir,"pages","current-snow.qmd")
    if(!file.exists(image) || file.info(image)$size<10000 || !file.exists(page) ||
        !identical(unname(tools::md5sum(image)),publication$percent_md5) ||
        !identical(unname(tools::md5sum(page)),publication$page_md5) ||
        !identical(readBin(image,"raw",n=8),as.raw(c(137,80,78,71,13,10,26,10))))
      return(unavailable("Snow image/page checksums could not be verified."))
    reference<-file.path(root,"data","processed","snodas","az-nm-pad050","climatology",
      "wy2005-wy2025","daily","centered-05day",format(date,"%m-%d"))
    if(!file.exists(file.path(reference,"complete.csv"))) return(unavailable("Snow reference support is unavailable."))
    marker<-utils::read.csv(file.path(reference,"complete.csv"))
    paths<-file.path(reference,c("median_swe.tif","sample_years.tif"))
    if(nrow(marker)!=1L || !all(c("month_day","reference_years","median_swe_md5","sample_years_md5") %in% names(marker)) ||
        marker$month_day!=format(date,"%m-%d") || !all(file.exists(paths)) ||
        marker$reference_years!=paste(2005:2025,collapse=",") ||
        !identical(unname(tools::md5sum(paths)),c(marker$median_swe_md5,marker$sample_years_md5)))
      return(unavailable("Snow reference checksums could not be verified."))
    median<-terra::rast(paths[1]); years<-terra::rast(paths[2])
    if(!terra::compareGeom(median,years,stopOnError=FALSE)) return(unavailable("Snow reference grids differ."))
    m<-terra::values(median,mat=FALSE); n<-terra::values(years,mat=FALSE)
    supported<-sum(is.finite(m) & is.finite(n) & m>=1 & n>=18)
    if(supported<minimum_reference_cells) return(unavailable("Too few cells have a supported typical snowpack."))
    list(available=TRUE,date=as.character(date),reference_cells=supported,
      image="maps/generated/snodas/current/swe-percent-median.png",page="pages/current-snow.qmd")
  },error=function(e) unavailable("Snow comparison/reference unavailable; showing dry-spell rank."))
}

map_dashboard_page_text <- function(dashboard, expected_data_dates = NULL, snow=NULL,archive_years=integer()) {
  grouped<-identical(as.character(dashboard$id),c("pcpn_total_07day","pcpn_percentile_30day",
    "pcpn_percentile_90day","pcpn_water_year_percentile","tmean_departure_30day",
    "pcpn_current_dry_spell_percentile"))
  lines <- c(
    "---",
    'title: "Current Conditions"',
    'subtitle: "Southwest Climate Watch"',
    "page-layout: full",
    "toc: false",
    "body-classes: dashboard-page",
    "filters: [filters/dashboard-status.lua]",
    "---",
    "",
    "::: {.dashboard-heading}",
    "::: {.dashboard-heading-title}",
    "# Current Conditions",
    "",
    "Southwest Climate Watch",
    ":::",
    "",
    "::: {.dashboard-status}",
    "**Site updated:** [Recorded at render time]{.dashboard-rendered-at}",
    "",
    paste0("**PRISM through:** ",gsub(" through ",": ",sub("^Data through ","",map_dashboard_date_line(expected_data_dates)),fixed=TRUE)),
    ":::",
    ":::",
    "",
    "::: {.dashboard-tool-links}",
    "[Daily Explorer \u2014 investigate individual days](pages/daily-explorer.qmd){.dashboard-tool-link}",
    "",
    "[Station Conditions \u2014 local observations and records](pages/station-conditions.qmd){.dashboard-tool-link}",
    "",
    "[Current Snow \u2014 snow storage and recent changes](pages/current-snow.qmd){.dashboard-tool-link}",
    "",
    "[Historic Seasons \u2014 compare completed years](#historic-seasons){.dashboard-tool-link}",
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
    snow_card<-identical(product$id,"pcpn_current_dry_spell_percentile") && isTRUE(snow$available)
    if(snow_card) {image<-snow$image; page<-snow$page; alt<-"Snow water equivalent as percent of the date-specific median"}
    if(grouped && index %in% c(1L,3L,5L)) {
      heading<-c("Recent rainfall","Seasonal context",if(isTRUE(snow$available)) "Temperature and snow" else "Temperature and dry spells")[(index+1L)%/%2L]
      lines<-c(lines,"::: {.dashboard-row-heading}",paste0("## ",heading),":::","")
    }
    lines <- c(
      lines,
      "::: {.dashboard-map-card}",
      paste0("[![](", image, '){fig-alt="', alt, '"', loading, "}](", page, ")"),
      "",
      if(snow_card) paste0("::: {.dashboard-source-note}\nSNODAS \u00b7 ",snow$date,
        " \u00b7 Daily median reference: WY2005\u20132025\n:::\n") else character(),
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
    "PRISM percentile ranks compare matching periods in 1991\u20132020. Low precipitation ranks indicate drier conditions. Temperature departure is in \u00b0F; positive values mean warmer conditions. A high dry-spell rank means an unusually long ongoing dry spell. These indicators describe conditions, not a combined drought classification.",
    "",
    "Water-year precipitation starts October 1. Early-season ranks describe a short period; use the 90-day map for broader context.",
    if(isTRUE(snow$available)) "\nSnow percentages are not percentile ranks. Ratios use typical SWE of at least 1 inch and at least 18 reference years; the snow date and reference differ from PRISM." else character(),
    ":::",
    "",
    "::: {#historic-seasons .dashboard-history-links}",
    "## Compare historic seasons",
    "Browse completed water years:",
    paste0(vapply(head(sort(unique(archive_years),decreasing=TRUE),5L),function(year) paste0("[WY",year,
      "](pages/archive/wy",year,".qmd)"),character(1)),collapse=" \u00b7 "),
    "",
    "Additional completed years are listed under Historic Years in the navigation menu.",
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
  temporarily_unavailable <- map_product_early_water_year_three_day(
    products, expected_data_dates)

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
    waiting <- temporarily_unavailable[[index]]
    freshness_checked <- isTRUE(product$enabled) && !waiting &&
      !seasonal && !is.na(expected_date)
    freshness_ok <- !freshness_checked || (
      !is.na(companion$date) && companion$date == expected_date
    )

    problems <- character()
    if (waiting) {
      if (!file.exists(page_path)) problems <- c(problems, "waiting source page is missing")
      if (!navigation_link) problems <- c(problems, "navigation link is missing")
      if (!any(grepl("Not yet available.", page_text, fixed = TRUE)) ||
          !any(grepl(format(expected_date), page_text, fixed = TRUE))) {
        problems <- c(problems, "waiting source page is stale or incorrect")
      }
      if (page_image_link || page_download_link) {
        problems <- c(problems, "waiting source page still links an old map")
      }
      if (isTRUE(require_rendered)) {
        if (!file.exists(rendered_path)) problems <- c(problems, "rendered waiting page is missing")
        if (!any(grepl("Not yet available.", rendered_text, fixed = TRUE)) ||
            !any(grepl(format(expected_date), rendered_text, fixed = TRUE))) {
          problems <- c(problems, "rendered waiting page is stale or incorrect")
        }
        if (rendered_image_link || rendered_download_link) {
          problems <- c(problems, "rendered waiting page still links an old map")
        }
      }
    } else if (isTRUE(product$enabled)) {
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
      actual_data_date = if (waiting || is.na(companion$date)) NA_character_ else format(companion$date),
      expected_data_date = if (is.na(expected_date)) NA_character_ else format(expected_date),
      freshness_policy = if (waiting) "awaiting-three-day-period" else
        if (seasonal) "seasonal-retention" else
          if (freshness_checked) "current" else "not-checked",
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
    "      - section: Current Maps",
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
  c(lines,
    "          - href: pages/current-snow.qmd",
    "            text: Snow",
    "      # END GENERATED MAP BROWSER")
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
    status_path = file.path("data", "diagnostics", "map-product-status.csv"),
    today=Sys.Date(),dashboard_snow_selector=map_dashboard_snow_selection) {
  products <- read_map_product_config(config_path)
  temporarily_unavailable <- map_product_early_water_year_three_day(
    products, expected_data_dates)
  enabled <- products[products$enabled, , drop = FALSE]
  dashboard <- read_map_dashboard_config(config_path, products)
  snow_config<-attr(dashboard,"seasonal_snow")
  snow<-if(isTRUE(snow_config$enabled)) dashboard_snow_selector(site_dir=site_dir,today=today,
    minimum_reference_cells=snow_config$minimum_reference_cells,
    maximum_age_days=snow_config$maximum_age_days) else NULL
  if (isTRUE(require_images)) {
    image_paths <- file.path(site_dir, "maps", "generated",
                             products$image[products$enabled &
                                            !temporarily_unavailable])
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
    waiting <- temporarily_unavailable[match(enabled$id[[index]], products$id)]
    writeLines(
      if (waiting) map_product_early_water_year_three_day_page(
        enabled[index, , drop = FALSE], expected_data_dates[["Precipitation"]])
      else map_product_page_text(enabled[index, , drop = FALSE]),
      map_product_page_path(enabled$id[[index]], site_dir),
      useBytes = TRUE
    )
  }
  writeLines(
    map_dashboard_page_text(dashboard, expected_data_dates,snow=snow,
      archive_years=as.integer(sub("^wy([0-9]{4})\\.qmd$","\\1",
        list.files(file.path(site_dir,"pages","archive"),pattern="^wy[0-9]{4}\\.qmd$")))),
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

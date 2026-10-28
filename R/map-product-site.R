# Generate the map-product pages and Quarto navigation from one configuration.

# Supported metrics and cached grid paths are coupled to the map product.
map_dashboard_summary_spec <- function(id) {
  if (grepl("^pcpn_total_[0-9]+day$",id)) {
    days <- as.integer(sub("^pcpn_total_([0-9]+)day$","\\1",id))
    return(list(path=file.path("accumulation","pcpn",sprintf("%02dday",days)),
      metrics=c("regional_mean","area_above_threshold"),type="precipitation",period=paste0(days," days")))
  }
  if (grepl("^pcpn_percentile_[0-9]+day$",id)) {
    days <- as.integer(sub("^pcpn_percentile_([0-9]+)day$","\\1",id))
    return(list(path=file.path("percentile-rank","pcpn",sprintf("%02dday",days)),
      metrics=c("area_below_percentile","area_above_percentile"),type="percentile",period=paste0(days," days")))
  }
  if (id=="pcpn_water_year_percentile") return(list(path=file.path("water-year","pcpn","percentile-rank"),
    metrics=c("area_below_percentile","area_above_percentile"),type="percentile",period="Water year to date"))
  if (grepl("^(tmean|maxt|mint)_departure_[0-9]+day$",id)) {
    variable <- sub("_.*$","",id); days <- as.integer(sub("^.*_([0-9]+)day$","\\1",id))
    return(list(path=file.path("rolling-departure",variable,sprintf("%03dday",days)),
      metrics="regional_mean",type="temperature",period=paste0(days," days")))
  }
  if (id=="pcpn_current_dry_spell_percentile") return(list(path=file.path("dry-spell","pcpn","percentile-rank"),
    metrics="area_above_percentile",type="dry_spell",period="Ongoing dry spell"))
  NULL
}

map_dashboard_validate_summaries <- function(config, products, ids) {
  layout <- config$summary_layout %||% "per_map"
  if(length(layout)!=1L || !layout %in% c("per_map","none"))
    stop("dashboard.summary_layout must be per_map or none.")
  summaries <- config$summaries %||% list()
  if(length(summaries) && (is.null(names(summaries)) || anyDuplicated(names(summaries)) ||
      any(!names(summaries) %in% products$id))) stop("Unknown or duplicate dashboard summary product.")
  for(id in names(summaries)) {
    settings <- summaries[[id]]
    if(!is.list(settings)) stop("Dashboard summary settings must be a mapping: ",id)
    settings$enabled <- settings$enabled %||% TRUE
    if(!is.logical(settings$enabled) || length(settings$enabled)!=1L || is.na(settings$enabled))
      stop("Dashboard summary enabled must be true or false: ",id)
    if(!settings$enabled) {summaries[[id]]<-settings; next}
    spec <- map_dashboard_summary_spec(id)
    metrics <- unlist(settings$metrics,use.names=FALSE)
    if(is.null(spec) || !length(metrics) || anyDuplicated(metrics) || any(!metrics %in% spec$metrics))
      stop("Incompatible or unsupported dashboard summary metric: ",id)
    settings$metrics <- as.character(metrics)
    for(field in intersect(names(settings),c("threshold_inches","lower_percentile","upper_percentile",
        "highlight_area_percent","strong_area_percent","mixed_area_percent"))) {
      x <- settings[[field]]
      if(!is.numeric(x) || length(x)!=1L || !is.finite(x) || x<0 ||
          (field!="threshold_inches" && x>100)) stop("Invalid dashboard summary threshold: ",field)
    }
    settings$threshold_inches <- settings$threshold_inches %||% .1
    settings$lower_percentile <- settings$lower_percentile %||% 10
    settings$upper_percentile <- settings$upper_percentile %||% 90
    settings$highlight_area_percent <- settings$highlight_area_percent %||% 10
    settings$strong_area_percent <- settings$strong_area_percent %||% 25
    if(settings$highlight_area_percent>=settings$strong_area_percent) stop("Summary color thresholds must be ordered.")
    if(settings$lower_percentile>=settings$upper_percentile) stop("Summary percentile thresholds must be ordered.")
    settings$label <- settings$label %||% spec$period
    if(!is.character(settings$label) || length(settings$label)!=1L || is.na(settings$label) ||
        !nzchar(settings$label) || grepl("[<>\\[\\]{}\r\n]",settings$label,perl=TRUE)) stop("Invalid summary label.")
    summaries[[id]] <- settings
  }
  groups <- config$groups %||% list()
  if(length(groups)) {
    group_ids <- unlist(lapply(groups,function(g) g$products),use.names=FALSE)
    if(!identical(as.character(group_ids),ids)) stop("Dashboard groups must list the selected products once, in display order.")
    if(any(!vapply(groups,function(g) is.character(g$title) && length(g$title)==1L &&
        !is.na(g$title) && nzchar(g$title) && !grepl("[\r\n]",g$title),logical(1)))) stop("Invalid dashboard group title.")
  }
  list(layout=layout,summaries=summaries,groups=groups,
    headlines=map_dashboard_validate_headlines(config$headlines,products))
}

map_dashboard_validate_headlines <- function(config,products) {
  if(is.null(config)) return(list(enabled=FALSE,cards=list()))
  if(!is.list(config) || !is.logical(config$enabled) || length(config$enabled)!=1L || is.na(config$enabled))
    stop("dashboard.headlines.enabled must be true or false.")
  if(!config$enabled) return(list(enabled=FALSE,cards=list()))
  cards <- config$cards
  if(!is.list(cards) || length(cards)<1L || length(cards)>3L) stop("Choose one to three headline cards.")
  ids <- vapply(cards,function(card) {
    id <- card$product
    if(!is.character(id) || length(id)!=1L || !id %in% products$id || !products$enabled[match(id,products$id)])
      stop("Headline cards must link to an enabled map product.")
    spec <- map_dashboard_summary_spec(id)
    if(is.null(spec) || !spec$type %in% c("percentile","temperature")) stop("Unsupported headline map type.")
    if(is.null(card$title) || !is.character(card$title) || length(card$title)!=1L || is.na(card$title) ||
        !nzchar(card$title) || grepl("[<>\\[\\]{}\r\n]",card$title,perl=TRUE)) stop("Invalid headline title.")
    id
  },character(1))
  if(anyDuplicated(ids)) stop("Headline map products must be unique.")
  normalized <- lapply(seq_along(cards),function(i) {
    card <- cards[[i]]; id <- ids[[i]]
    card$metrics <- if(map_dashboard_summary_spec(id)$type=="temperature") "regional_mean" else
      c("area_below_percentile","area_above_percentile")
    card$lower_percentile <- card$lower_percentile %||% 33
    card$upper_percentile <- card$upper_percentile %||% 67
    card$highlight_area_percent <- card$highlight_area_percent %||% 50
    card$strong_area_percent <- card$strong_area_percent %||% 67
    card$mixed_area_percent <- card$mixed_area_percent %||% 25
    card$show_period <- card$show_period %||% TRUE
    if(!is.logical(card$show_period) || length(card$show_period)!=1L || is.na(card$show_period))
      stop("Headline show_period must be true or false.")
    map_dashboard_validate_summaries(list(summaries=setNames(list(card),id)),products,id)$summaries[[id]]
  })
  names(normalized) <- ids
  list(enabled=TRUE,cards=normalized)
}

map_dashboard_regional_value <- function(values, weights, metric, settings=list(),min_coverage=.98) {
  inside <- is.finite(weights) & weights>0
  good <- inside & is.finite(values)
  area <- sum(weights[inside])
  if(area<=0 || sum(weights[good])/area<min_coverage) return(NA_real_)
  if(metric=="regional_mean") return(stats::weighted.mean(values[good],weights[good]))
  test <- switch(metric,
    area_above_threshold=values >= settings$threshold_inches-1e-7,
    area_below_percentile=values < settings$lower_percentile,
    area_above_percentile=values > settings$upper_percentile)
  100*sum(weights[good & test])/sum(weights[good])
}

map_dashboard_summary_text <- function(summary) {
  if(is.null(summary)) return(character())
  escape <- function(x) {
    for(pair in list(c("&","&amp;"),c("<","&lt;"),c(">","&gt;"),c('"',"&quot;")))
      x <- gsub(pair[1],pair[2],x,fixed=TRUE)
    x
  }
  if(any(!is.finite(summary$values))) return('<span class="dashboard-summary-chip summary-neutral">Summary unavailable</span>')
  settings <- summary$settings
  chips <- vapply(names(summary$values),function(metric) {
    value <- summary$values[[metric]]
    text <- switch(metric,
      regional_mean=if(summary$type=="temperature") sprintf("%+.1f\u00b0F from normal",value)
        else sprintf("%.2f\u2033 avg",value),
      area_above_threshold=sprintf("\u2265%.2f\u2033: %.0f%%",settings$threshold_inches,value),
      area_below_percentile=sprintf("Very dry: %.0f%%",value),
      area_above_percentile=if(summary$type=="dry_spell") sprintf("Long dry spells: %.0f%%",value) else sprintf("Very wet: %.0f%%",value))
    tone <- "neutral"; strong <- FALSE
    if(metric=="regional_mean" && summary$type=="temperature") {
      tone <- if(value < -.5) "cool" else if(value>.5) "warm" else "neutral"
      strong <- abs(value)>=3
    }
    if(metric %in% c("area_below_percentile","area_above_percentile")) {
      if(value >= (settings$highlight_area_percent %||% 10))
        tone <- if(metric=="area_below_percentile" || summary$type=="dry_spell") "dry" else "wet"
      strong <- value >= (settings$strong_area_percent %||% 25)
    }
    detail <- switch(metric,
      regional_mean=if(summary$type=="temperature") "Area-weighted temperature departure" else "Area-weighted precipitation total",
      area_above_threshold=sprintf("Area with accumulated precipitation at least %.2f inches",settings$threshold_inches),
      area_below_percentile=sprintf("Area below percentile %g",settings$lower_percentile),
      area_above_percentile=sprintf("Area above percentile %g",settings$upper_percentile))
    paste0('<span class="dashboard-summary-chip summary-',tone,if(strong && tone!="neutral") ' summary-strong' else '',
      '" title="',escape(paste0("AZ + NM; ",detail,"; through ",summary$date)),
      '">',escape(text),'</span>')
  },character(1))
  paste0('<span class="dashboard-summary-period">',escape(summary$label),'</span> ',paste(chips,collapse=" "))
}

# Cache only the configured visible metrics; no new data/reference calculations.
map_dashboard_summaries <- function(dates, root=".",weights_function=NULL,dashboard=read_map_dashboard_config(),
    cache_name="regional-summaries.rds") {
  configured <- attr(dashboard,"summary_config")
  if(!identical(configured$layout,"per_map")) return(list())
  settings <- configured$summaries[intersect(dashboard$id,names(configured$summaries))]
  settings <- Filter(function(x) isTRUE(x$enabled),settings)
  if(!length(settings)) return(list())
  date_for <- function(id) {
    key <- if(map_dashboard_summary_spec(id)$type=="temperature") "Temperature" else "Precipitation"
    if(!is.null(dates) && key %in% names(dates)) as.character(dates[[key]]) else NA_character_
  }
  files <- vapply(names(settings),function(id) file.path(root,"data","processed","prism","az-nm-pad050","daily",
    map_dashboard_summary_spec(id)$path,paste0(date_for(id),".tif")),character(1))
  signature <- digest::digest(list(version=3L,settings=settings,files=files,
    md5=unname(tools::md5sum(files)),terra=as.character(utils::packageVersion("terra")),
    maps=as.character(utils::packageVersion("maps"))))
  cache_path <- file.path(root,"data","processed","dashboard",cache_name)
  cache <- if(file.exists(cache_path)) tryCatch(readRDS(cache_path),error=function(e) NULL) else NULL
  if(is.null(weights_function) && identical(cache$signature,signature)) return(cache$summaries)
  masks <- new.env(parent=emptyenv())
  if(is.null(weights_function)) weights_function <- function(raster) {
    key <- digest::digest(c(terra::nrow(raster),terra::ncol(raster),as.vector(terra::ext(raster)),terra::crs(raster)))
    if(exists(key,masks,inherits=FALSE)) return(get(key,masks))
    states <- sf::st_as_sf(maps::map("state",regions=c("arizona","new mexico"),fill=TRUE,plot=FALSE))
    mask <- terra::rasterize(terra::project(terra::vect(states),terra::crs(raster)),raster,field=1,background=NA)
    weights <- terra::values(terra::cellSize(raster,unit="km"),mat=FALSE)
    weights[!is.finite(terra::values(mask,mat=FALSE))] <- 0
    assign(key,weights,masks); weights
  }
  summaries <- lapply(names(settings),function(id) {
    spec <- map_dashboard_summary_spec(id); setting <- settings[[id]]; note <- ""
    values <- tryCatch({
      if(!file.exists(files[[id]])) stop("Derived grid unavailable")
      raster <- terra::rast(files[[id]])
      if(terra::nlyr(raster)!=1L) stop("Expected a single derived layer")
      data <- terra::values(raster,mat=FALSE)
      if(spec$type %in% c("percentile","dry_spell") && any(data[is.finite(data)]<0 | data[is.finite(data)]>100))
        stop("Invalid percentile grid")
      weights <- weights_function(raster)
      setNames(vapply(setting$metrics,function(metric) map_dashboard_regional_value(data,weights,metric,setting),numeric(1)),setting$metrics)
    },error=function(e) {note <<- conditionMessage(e); setNames(rep(NA_real_,length(setting$metrics)),setting$metrics)})
    list(id=id,type=spec$type,values=values,date=date_for(id),label=setting$label,settings=setting,note=note)
  })
  names(summaries) <- names(settings)
  dir.create(dirname(cache_path),recursive=TRUE,showWarnings=FALSE)
  saveRDS(list(signature=signature,summaries=summaries),cache_path)
  summaries
}

map_dashboard_headlines <- function(dates,root=".",dashboard=read_map_dashboard_config(),weights_function=NULL) {
  cards <- attr(dashboard,"summary_config")$headlines
  if(!isTRUE(cards$enabled)) return(list())
  # Headline maps need not appear in the six-map grid.
  dashboard <- data.frame(id=names(cards$cards),stringsAsFactors=FALSE)
  attr(dashboard,"summary_config") <- list(layout="per_map",summaries=cards$cards)
  map_dashboard_summaries(dates,root,weights_function,dashboard,cache_name="headline-summaries.rds")
}

map_dashboard_headline_tone <- function(summary) {
  if(any(!is.finite(summary$values))) return("neutral")
  if(summary$type=="temperature") {
    value <- summary$values[["regional_mean"]]
    tone <- if(value < -.5) "cool" else if(value>.5) "warm" else "neutral"
    return(paste0(tone,if(abs(value)>=3) " headline-strong" else ""))
  }
  low <- summary$values[["area_below_percentile"]]; high <- summary$values[["area_above_percentile"]]
  settings <- summary$settings
  if(low>=settings$mixed_area_percent && high>=settings$mixed_area_percent) return("mixed")
  if(max(low,high)<settings$highlight_area_percent) return("neutral")
  paste0(if(low>high) "dry" else "wet",if(max(low,high)>=settings$strong_area_percent) " headline-strong" else "")
}

map_dashboard_headline_text <- function(headlines) {
  if(!length(headlines)) return(character())
  lines <- c("::: {.dashboard-headlines}")
  for(summary in headlines) {
    settings <- summary$settings
    tone <- map_dashboard_headline_tone(summary)
    missing <- any(!is.finite(summary$values))
    values <- if(missing) "Summary unavailable" else if(summary$type=="temperature")
      paste0('<div class="headline-metrics headline-temperature"><span><strong>',
        sprintf("%+.1f\u00b0F",summary$values[["regional_mean"]]),
        '</strong><small>from normal</small></span></div>') else
      paste0('<div class="headline-metrics"><span><strong>',
        sprintf("%.0f%%",summary$values[["area_below_percentile"]]),
        '</strong><small>below normal</small></span><span><strong>',
        sprintf("%.0f%%",summary$values[["area_above_percentile"]]),
        '</strong><small>above normal</small></span></div>')
    date <- as.Date(summary$date)
    through <- if(is.na(date)) "Date unavailable" else paste0("Through ",format(date,"%b %d, %Y"))
    lines <- c(lines,paste0("::: {.dashboard-headline .headline-",gsub(" "," .",tone,fixed=TRUE),"}"),
      paste0("### [",settings$title,"](pages/products/",summary$id,".qmd){.headline-link}"),"",
      if(!identical(settings$show_period,FALSE)) paste0("[",summary$label,"]{.headline-period}") else character(),"",values,"",
      paste0("[AZ + NM \u00b7 ",through,"]{.headline-date}"),":::","")
  }
  c(lines,":::","")
}


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
  attr(dashboard,"summary_config") <- map_dashboard_validate_summaries(config$dashboard,products,ids)
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

map_dashboard_page_text <- function(dashboard, expected_data_dates = NULL, snow=NULL,archive_years=integer(),
    roni=swc_read_dashboard_roni(), summaries=NULL,headlines=NULL) {
  summary_config <- attr(dashboard,"summary_config")
  groups <- summary_config$groups
  lines <- c(
    "---",
    'title: "Current Conditions"',
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
    ":::",
    "",
    "::: {.dashboard-status}",
    "**Site updated:** [Recorded at render time]{.dashboard-rendered-at}",
    "",
    paste0("**PRISM through:** ",gsub(" through ",": ",sub("^Data through ","",map_dashboard_date_line(expected_data_dates)),fixed=TRUE)),
    ":::",
    ":::",
    "",
    swc_dashboard_roni_text(roni),
    map_dashboard_headline_text(headlines),
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
    for(group in groups) if(identical(product$id,as.character(group$products[[1L]]))) {
      heading <- if(isTRUE(snow$available) && !is.null(group$snow_title)) group$snow_title else group$title
      lines<-c(lines,"::: {.dashboard-row-heading}",paste0("## ",heading),":::","")
    }
    lines <- c(
      lines,
      "::: {.dashboard-map-card}",
      if(!snow_card && identical(summary_config$layout,"per_map"))
        c("::: {.dashboard-map-summary}",map_dashboard_summary_text(summaries[[product$id]]),":::","") else character(),
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
    "",
    "Map summaries describe combined Arizona and New Mexico, weighted by grid-cell area within state boundaries. At least 98% valid area is required. Percentile summaries show area below or above the stated thresholds; they do not average pixel percentiles. Rainfall coverage uses the stated accumulation threshold. Each summary follows its map's period and data date.",
    "",
    "Very dry/wet: percentage of AZ/NM area below the 10th/above the 90th precipitation percentile by default. Long dry spells uses the high tail. Stronger chip colors indicate a larger affected area, not greater severity; gray indicates a smaller footprint. Temperature colors indicate cooler/warmer departures, not a significance test. Hover over a value for its configured threshold and date. Rainfall amounts remain neutral because amount alone does not establish rarity.",
    "",
    if(length(headlines)) "Headline precipitation cards show area below the 33rd/above the 67th percentile by default. Brown/teal indicates widespread below-/above-normal conditions; mixed shading retains both signals. These display cues are not regional percentile ranks or drought classifications. Headline temperature is an area-weighted departure from 1991\u20132020 normal.",
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
    "::: {.dashboard-explore-more}",
    "**Explore more:** [Daily Explorer](pages/daily-explorer.qmd) \u00b7 [Station Conditions](pages/station-conditions.qmd) \u00b7 [Current Snow](pages/current-snow.qmd) \u00b7 [Historic Seasons](#historic-seasons)",
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
      headlines=map_dashboard_headlines(expected_data_dates,
        root=dirname(normalizePath(site_dir,winslash="/",mustWork=TRUE)),dashboard=dashboard),
      summaries=map_dashboard_summaries(expected_data_dates,
        root=dirname(normalizePath(site_dir,winslash="/",mustWork=TRUE)),dashboard=dashboard),
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

# Latest published CPC three-month RONI; never average three seasonal values.
swc_roni_url <- "https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso/roni/"
swc_enso_status_url <- "https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso_advisory/ensodisc.shtml"

swc_roni_strength_label <- function(value) {
  if(!is.numeric(value) || length(value)!=1L || !is.finite(value)) stop("Expected a finite RONI value.")
  magnitude <- abs(value)
  if(magnitude < .5) return("Neutral-range conditions")
  strength <- if(magnitude>=2) "Very strong" else if(magnitude>=1.5) "Strong" else
    if(magnitude>=1) "Moderate" else "Weak"
  paste0(strength,if(value>0) " El Ni\u00f1o" else " La Ni\u00f1a","-range conditions")
}

swc_parse_enso_status <- function(html,today=Sys.Date()) {
  doc <- xml2::read_html(html)
  text <- gsub("[[:space:]\u00a0]+"," ",xml2::xml_text(xml2::xml_find_first(doc,"//body")),perl=TRUE)
  if(!grepl("ENSO Alert System Status:.*Synopsis:",text)) stop("CPC advisory status not recognized.")
  status <- trimws(sub("^.*ENSO Alert System Status:(.*?)Synopsis:.*$","\\1",text,perl=TRUE))
  status <- gsub("\u00f1","n",status,fixed=TRUE)
  allowed <- c("El Nino Advisory"="El Ni\u00f1o Advisory","La Nina Advisory"="La Ni\u00f1a Advisory",
    "El Nino Watch"="El Ni\u00f1o Watch","La Nina Watch"="La Ni\u00f1a Watch",
    "Final El Nino Advisory"="Final El Ni\u00f1o Advisory","Final La Nina Advisory"="Final La Ni\u00f1a Advisory",
    "Not Active"="Not Active")
  parts <- trimws(strsplit(status,"/",fixed=TRUE)[[1]])
  if(!length(parts) || any(!parts %in% names(allowed))) stop("Unrecognized CPC advisory category.")
  header <- sub("ENSO Alert System Status:.*$","",text)
  date_text <- regmatches(header,regexpr("[0-9]{1,2} (January|February|March|April|May|June|July|August|September|October|November|December) [0-9]{4}",header,perl=TRUE))
  if(length(date_text)!=1L || !nzchar(date_text)) stop("CPC issue date missing.")
  bits <- strsplit(date_text," ",fixed=TRUE)[[1]]
  month <- match(bits[2],c("January","February","March","April","May","June","July","August","September","October","November","December"))
  issued <- as.Date(sprintf("%04d-%02d-%02d",as.integer(bits[3]),month,as.integer(bits[1])))
  if(is.na(issued) || issued>as.Date(today)) stop("Invalid or future CPC issue date.")
  list(status=paste(unname(allowed[parts]),collapse=" / "),issued=issued)
}

swc_read_enso_status <- function(path=file.path("data","processed","roni","enso-status.rds"),
    today=Sys.Date(),refresh=FALSE,fetch=function() {
      httr2::resp_body_string(httr2::req_perform(httr2::req_timeout(httr2::request(swc_enso_status_url),15)))
    }) {
  cache <- if(file.exists(path)) tryCatch(suppressWarnings(readRDS(path)),error=function(e) NULL) else NULL
  valid <- function(x) is.list(x) && is.character(x$status) && length(x$status)==1L &&
    !is.na(x$status) && inherits(x$issued,"Date") && length(x$issued)==1L &&
    !is.na(x$issued) && x$issued<=as.Date(today) && is.character(x$checked) && length(x$checked)==1L
  if(!valid(cache)) cache <- NULL
  if(refresh && (is.null(cache) || !identical(cache$checked,as.character(today)))) cache <- tryCatch({
    next_status <- swc_parse_enso_status(fetch(),today)
    if(!is.null(cache) && next_status$issued<cache$issued) stop("CPC response predates the cached advisory.")
    next_status$checked <- as.character(today)
    dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
    saveRDS(next_status,path); next_status
  },error=function(e) {
    message("ENSO status refresh unavailable; retaining dated cache if available: ",conditionMessage(e)); cache
  })
  if(is.null(cache)) return(NULL)
  c(cache,list(cached=!identical(cache$checked,as.character(today)),
    stale=as.integer(as.Date(today)-cache$issued)>45L))
}

swc_dashboard_enso_status_text <- function(status=NULL) {
  link <- paste0("[CPC discussion](",swc_enso_status_url,")")
  if(is.null(status)) return(paste0("**NOAA status:** unavailable. ",link))
  paste0(if(isTRUE(status$stale)) "**Last reported NOAA status:** " else "**NOAA status:** ",status$status,
    " \u00b7 issued ",format(status$issued,"%b %d, %Y"),". ",link,
    if(isTRUE(status$cached) || isTRUE(status$stale)) paste0(" \u00b7 Source last checked ",status$checked,
      if(isTRUE(status$stale)) "; advisory is over 45 days old." else " (cached).") else "")
}

swc_parse_roni <- function(html, today = Sys.Date()) {
  document <- xml2::read_html(html)
  rows <- xml2::xml_find_all(document, ".//tr")
  records <- lapply(rows, function(row) {
    cells <- trimws(xml2::xml_text(xml2::xml_find_all(row, "./td|./th")))
    if (length(cells) < 2L || length(cells) > 13L || !grepl("^[12][0-9]{3}$", cells[1L])) return(NULL)
    year <- as.integer(cells[1L])
    values <- suppressWarnings(as.numeric(cells[-1L]))
    length(values) <- 12L
    # Table year is the middle month: DJF ends February, NDJ ends next January.
    ends <- as.Date(sprintf("%04d-%02d-01", year + (2:13 > 12), (2:13 - 1L) %% 12L + 1L))
    data.frame(period = c("DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ",
      "JJA", "JAS", "ASO", "SON", "OND", "NDJ"), end_month = ends, value = values)
  })
  values <- do.call(rbind, records)
  if (is.null(values)) stop("CPC RONI table not recognized.")
  current_month <- as.Date(format(as.Date(today), "%Y-%m-01"))
  values <- values[is.finite(values$value) & abs(values$value) < 10 &
    values$end_month < current_month, , drop = FALSE]
  if (!nrow(values) || anyDuplicated(values$end_month)) stop("No unique completed RONI periods.")
  values[which.max(values$end_month), , drop = FALSE]
}

swc_read_dashboard_roni <- function(path = file.path("data", "processed", "roni", "latest.rds"),
    today = Sys.Date(), refresh = FALSE, fetch = function() {
      response <- httr2::req_perform(httr2::req_timeout(httr2::request(swc_roni_url), 15))
      httr2::resp_body_string(response)
    }) {
  cached <- if (file.exists(path)) tryCatch(suppressWarnings(readRDS(path)), error = function(e) NULL) else NULL
  valid <- function(x) is.list(x) && is.data.frame(x$data) && nrow(x$data) == 1L &&
    all(c("period", "end_month", "value") %in% names(x$data)) &&
    is.finite(x$data$value) && inherits(x$data$end_month, "Date") &&
    !is.na(x$data$end_month) && x$data$end_month < as.Date(format(today, "%Y-%m-01"))
  if (!valid(cached)) cached <- NULL
  if (refresh && (is.null(cached) || !identical(cached$checked, as.character(today)))) {
    cached <- tryCatch({
      result <- list(data = swc_parse_roni(fetch(), today), checked = as.character(today))
      if (!is.null(cached) && result$data$end_month < cached$data$end_month)
        stop("CPC response is older than the cached period.")
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      saveRDS(result, path)
      result
    }, error = function(e) {
      message("RONI refresh unavailable; retaining dated cache if available: ", conditionMessage(e))
      cached
    })
  }
  if (is.null(cached)) return(NULL)
  c(as.list(cached$data[1L, ]), list(checked = cached$checked,
    cached = !identical(cached$checked, as.character(today))))
}

swc_dashboard_roni_text <- function(roni = NULL,status=swc_read_enso_status()) {
  if (is.null(roni)) return(c("::: {.archive-year-intro .dashboard-roni}",
    "**Latest three-month RONI:** unavailable.", "",
    paste0("[NOAA CPC source](", swc_roni_url, ")"),"",swc_dashboard_enso_status_text(status), ":::", ""))
  value <- roni$value
  category <- if (value >= .5) "el-nino" else if (value <= -.5) "la-nina" else "neutral"
  label <- swc_roni_strength_label(value)
  end <- as.Date(roni$end_month)
  start <- seq(end, by = "-1 month", length.out = 3L)[3L]
  period <- paste0(format(start, "%b %Y"), "\u2013", format(end, "%b %Y"))
  c(paste0("::: {.archive-year-intro .dashboard-roni .archive-roni-", category, "}"),
    paste0("[", label, " \u00b7 RONI ", sprintf("%+.1f", value), " \u00b0C]{.archive-roni-badge}"),
    "", paste0("**", roni$period, " \u00b7 ", period, "** \u2014 latest published three-month period."),
    "",swc_dashboard_enso_status_text(status),
    "", paste0("Recent values are provisional; one period does not establish an ENSO episode. ",
      "[NOAA CPC](", swc_roni_url, ")", if (isTRUE(roni$cached))
      paste0(" \u00b7 Cached source last checked ", roni$checked, ".") else ""), ":::", "")
}

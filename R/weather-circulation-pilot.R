# Isolated CORe access/rendering pilot; never called by daily publication.
weather_core_url <- function(date) {
  date <- as.Date(date)
  if (length(date) != 1L || is.na(date) || date < as.Date("1950-01-01"))
    stop("Choose one CORe date since 1950-01-01.")
  paste0("https://storage.googleapis.com/noaa-nws-ncep-core/grib/day/pgb/",
    format(date, "%Y/%m/pgb.%Y%m%d"))
}

weather_core_plan <- function(lines, date, max_field_bytes = 1e6) {
  if (!is.character(lines) || !length(lines)) stop("Empty CORe index.")
  parts <- strsplit(lines[nzchar(trimws(lines))], ":", fixed = TRUE)
  if (any(lengths(parts) < 6L)) stop("Malformed CORe index.")
  offset <- suppressWarnings(as.numeric(vapply(parts, `[`, character(1), 2L)))
  if (any(!is.finite(offset)) || any(offset < 0) || any(offset != floor(offset)) ||
      any(diff(offset) <= 0)) stop("Index byte offsets must be strictly increasing integers.")
  rows <- data.frame(start = offset, end = c(offset[-1L] - 1, NA_real_),
    stamp = vapply(parts, `[`, character(1), 3L),
    variable = vapply(parts, `[`, character(1), 4L),
    level = vapply(parts, `[`, character(1), 5L),
    averaging = vapply(parts, `[`, character(1), 6L), stringsAsFactors = FALSE)
  keys <- c(height500 = "HGT:500 mb", u250 = "UGRD:250 mb", v250 = "VGRD:250 mb")
  positions <- vapply(keys, function(key) {
    found <- which(paste(rows$variable, rows$level, sep = ":") == key)
    if (length(found) != 1L) stop("Expected exactly one field: ", key)
    found
  }, integer(1))
  selected <- rows[positions, , drop = FALSE]
  selected$field <- names(keys)
  selected$bytes <- selected$end - selected$start + 1
  if (anyNA(selected$end) || any(selected$bytes <= 0 | selected$bytes > max_field_bytes))
    stop("Unbounded or oversized CORe record; no full-file download allowed.")
  if (any(selected$stamp != paste0("d=", format(as.Date(date), "%Y%m%d"), "00")) ||
      any(selected$averaging != "8@3 hour ave(anl),missing=0"))
    stop("Requested date or complete eight-sample daily averaging does not match the index.")
  selected
}

weather_core_check_response <- function(body, status, content_range, start, end) {
  expected <- sprintf("bytes %.0f-%.0f/", start, end)
  if (status != 206L || is.null(content_range) ||
      !startsWith(content_range, expected) || length(body) != end - start + 1)
    stop("Server did not return the exact requested byte range.")
  if (!is.raw(body) || length(body) < 20L ||
      !identical(body[1:4], charToRaw("GRIB")) || body[8L] != as.raw(2L) ||
      !identical(tail(body, 4L), charToRaw("7777"))) stop("Invalid GRIB2 record.")
  size <- sum(as.numeric(body[9:16]) * 256^(7:0))
  if (size != length(body)) stop("GRIB2 message length does not match its byte range.")
  invisible(TRUE)
}

weather_core_request <- function(url) {
  httr2::request(url) |>
    httr2::req_user_agent("SWClimateWatch-local-circulation-pilot") |>
    httr2::req_timeout(45) |>
    httr2::req_options(maxfilesize = 1e6)
}

weather_core_download <- function(date, directory, refresh = FALSE) {
  date <- as.Date(date); base <- weather_core_url(date)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  marker <- file.path(directory, "complete.rds")
  old <- if (file.exists(marker)) tryCatch(readRDS(marker), error = function(e) NULL) else NULL
  started <- proc.time()[["elapsed"]]
  if (!refresh && is.list(old) && identical(old$url, base) &&
      is.data.frame(old$files) && nrow(old$files) == 4L &&
      all(file.exists(old$files$path)) &&
      identical(unname(tools::md5sum(old$files$path)), old$files$md5)) {
    return(list(plan = old$plan, paths = old$paths, cached = TRUE,
      transferred_bytes = 0, requests = 0L, download_seconds = proc.time()[["elapsed"]] - started))
  }
  response <- httr2::req_perform(weather_core_request(paste0(base, ".idx")))
  if (httr2::resp_status(response) != 200L) stop("CORe index unavailable.")
  index_raw <- httr2::resp_body_raw(response)
  lines <- strsplit(rawToChar(index_raw), "\n", fixed = TRUE)[[1L]]
  plan <- weather_core_plan(trimws(lines), date)
  index_path <- file.path(directory, "source.idx")
  writeBin(index_raw, index_path)
  paths <- setNames(file.path(directory, paste0(plan$field, ".grb")), plan$field)
  transferred <- length(index_raw)
  for (i in seq_len(nrow(plan))) {
    field <- plan$field[i]
    request <- weather_core_request(paste0(base, ".grb")) |>
      httr2::req_headers(Range = sprintf("bytes=%.0f-%.0f", plan$start[i], plan$end[i]),
                        `Accept-Encoding` = "identity")
    response <- httr2::req_perform(request)
    body <- httr2::resp_body_raw(response)
    weather_core_check_response(body, httr2::resp_status(response),
      httr2::resp_header(response, "Content-Range"), plan$start[i], plan$end[i])
    writeBin(body, paths[[field]])
    transferred <- transferred + length(body)
  }
  all_paths <- c(index_path, unname(paths))
  files <- data.frame(path = all_paths, md5 = unname(tools::md5sum(all_paths)))
  saveRDS(list(url = base, plan = plan, paths = paths, files = files,
    initial_download = list(transferred_bytes = transferred, requests = 4L,
      seconds = proc.time()[["elapsed"]] - started)), marker)
  list(plan = plan, paths = paths, cached = FALSE, transferred_bytes = transferred,
    requests = 4L, download_seconds = proc.time()[["elapsed"]] - started)
}

weather_gaussian_latitudes <- function(n) {
  if (length(n) != 1L || !is.numeric(n) || !is.finite(n) || n < 2 ||
      n > 1024 || n != floor(n) || n %% 2 != 0) stop("Expected a bounded even Gaussian row count.")
  z <- cos(pi * (seq_len(n) - .25) / (n + .5))
  for (iteration in 1:20) {
    p0 <- rep(1, n); p1 <- z
    for (k in 2:n) {p2 <- ((2*k-1)*z*p1-(k-1)*p0)/k; p0 <- p1; p1 <- p2}
    derivative <- n * (z*p1-p0)/(z^2-1)
    next_z <- z-p1/derivative
    if (max(abs(next_z-z)) < 1e-14) return(sort(asin(next_z)*180/pi, decreasing = TRUE))
    z <- next_z
  }
  stop("Gaussian latitude calculation did not converge.")
}

weather_core_grid <- function(path) {
  body <- readBin(path, "raw", n = file.info(path)$size)
  uint <- function(x) sum(as.numeric(x)*256^rev(seq_along(x)-1))
  position <- 17L
  while (position < length(body)-4L) {
    size <- uint(body[position+(0:3)])
    if (size < 5 || position+size-1 > length(body)) stop("Invalid GRIB section length.")
    section <- body[position+seq_len(size)-1L]
    if (as.integer(section[5L]) == 3L) {
      if (length(section) != 72L || uint(section[13:14]) != 40L ||
          as.integer(section[72L]) != 0L || uint(section[39:42]) != 0)
        stop("Pilot requires an unrotated full Gaussian grid with standard scanning.")
      columns <- uint(section[31:34]); rows <- uint(section[35:38])
      if (rows != 2*uint(section[68:71]) || uint(section[7:10]) != rows*columns)
        stop("Unsupported reduced/partial Gaussian grid.")
      latitude <- weather_gaussian_latitudes(rows)
      if (abs(latitude[1L]-uint(section[47:50])/1e6) > 2e-6)
        stop("Gaussian latitude does not match the encoded first point.")
      return(list(section = section, rows = rows, columns = columns, latitude = latitude))
    }
    position <- position + size
  }
  stop("Missing GRIB grid definition.")
}

weather_core_decode <- function(paths, directory) {
  # Preserve GDAL metadata before interpreting units or Gaussian-grid handling.
  expected <- list(height500 = c("HGT", "[gpm]", "50000-ISBL"),
    u250 = c("UGRD", "[m/s]", "25000-ISBL"), v250 = c("VGRD", "[m/s]", "25000-ISBL"))
  rasters <- lapply(names(paths), function(field) {
    path <- paths[[field]]
    info <- terra::describe(path, print = FALSE)
    writeLines(info, file.path(directory, paste0(basename(path), "-metadata.txt")))
    required <- paste0(c("GRIB_ELEMENT=", "GRIB_UNIT=", "GRIB_SHORT_NAME="), expected[[field]])
    if (!all(vapply(required, function(text) any(grepl(text, info, fixed = TRUE)), logical(1))))
      stop("Unexpected field identity, pressure or units in GRIB metadata: ", field)
    terra::rast(path)
  })
  names(rasters) <- names(paths)
  if (any(vapply(rasters, terra::nlyr, numeric(1)) != 1L)) stop("Expected one layer per selected field.")
  terra::compareGeom(rasters[[1L]], rasters[[2L]], stopOnError = TRUE)
  terra::compareGeom(rasters[[2L]], rasters[[3L]], stopOnError = TRUE)
  grids <- lapply(paths, weather_core_grid)
  if (!all(vapply(grids, function(x) identical(x$section, grids[[1L]]$section), logical(1))) ||
      terra::nrow(rasters[[1L]]) != grids[[1L]]$rows ||
      terra::ncol(rasters[[1L]]) != grids[[1L]]$columns)
    stop("Grid definitions do not match decoded field geometry.")
  # GDAL exposes an affine approximation to the Gaussian latitude axis. Restore
  # true row-center latitudes from Gaussian quadrature before any plotting.
  attr(rasters, "gaussian_latitudes") <- grids[[1L]]$latitude
  rasters
}

weather_contour_labels <- function(data, breaks = seq(420, 630, 6)) {
  x <- sort(unique(data$x)); y <- sort(unique(data$y))
  z <- matrix(NA_real_, length(x), length(y))
  z[cbind(match(data$x, x), match(data$y, y))] <- data$height_dm
  contours <- grDevices::contourLines(x, y, z, levels = breaks)
  labels <- lapply(contours, function(line) {
    distance <- c(0, cumsum(sqrt((diff(line$x)*cos(40*pi/180))^2 + diff(line$y)^2)))
    total <- tail(distance, 1)
    if (total < 15) return(NULL)
    positions <- vapply(if (total > 85) c(.3,.7) else .5,
      function(f) which.min(abs(distance-f*total)), integer(1))
    data.frame(x=line$x[positions], y=line$y[positions], label=line$level)
  })
  labels <- do.call(rbind, labels)
  if (is.null(labels)) return(data.frame(x=numeric(), y=numeric(), label=numeric()))
  labels <- labels[labels$x > 124 & labels$x < 296 & labels$y > 12 & labels$y < 68, ]
  # Keep sparse, deterministic labels; avoid covering neighboring contours.
  keep <- logical(nrow(labels))
  for (i in seq_len(nrow(labels))) {
    prior <- which(keep)
    keep[i] <- !length(prior) || all(((labels$x[i]-labels$x[prior])/6)^2 +
      ((labels$y[i]-labels$y[prior])/2.5)^2 > 1)
  }
  labels[keep, ]
}

weather_streamlines <- function(data, step = .7, max_steps = 220L) {
  x <- sort(unique(data$x)); y <- sort(unique(data$y))
  if (length(x) < 2 || length(y) < 2) stop("Streamlines require a two-dimensional grid.")
  u <- v <- matrix(NA_real_, length(x), length(y))
  indices <- cbind(match(data$x,x), match(data$y,y))
  u[indices] <- data$u250; v[indices] <- data$v250
  inside <- function(p) all(is.finite(p)) && p[1] >= min(x) && p[1] < max(x) &&
    p[2] >= min(y) && p[2] < max(y)
  direction <- function(p) {
    if (!inside(p)) return(c(NA_real_,NA_real_))
    i <- findInterval(p[1],x); j <- findInterval(p[2],y)
    a <- (p[1]-x[i])/(x[i+1]-x[i]); b <- (p[2]-y[j])/(y[j+1]-y[j])
    interpolate <- function(m) (1-a)*(1-b)*m[i,j]+a*(1-b)*m[i+1,j]+
      (1-a)*b*m[i,j+1]+a*b*m[i+1,j+1]
    uv <- c(interpolate(u),interpolate(v))
    if (any(!is.finite(uv)) || sum(uv^2) < 1) return(c(NA_real_,NA_real_))
    d <- c(uv[1]/cos(p[2]*pi/180),uv[2])
    d/sqrt((d[1]*cos(40*pi/180))^2+d[2]^2)
  }
  key <- function(p) paste(floor(p[1]/4),floor(p[2]/2.5),sep=":")
  occupied <- new.env(hash=TRUE,parent=emptyenv())
  seeds <- expand.grid(x=seq(min(x)+2,max(x)-2,5), y=seq(min(y)+2,max(y)-2,3))
  paths <- list()
  for (s in seq_len(nrow(seeds))) {
    seed <- as.numeric(seeds[s,])
    if (exists(key(seed),occupied,inherits=FALSE)) next
    trace <- function(sign) {
      p <- seed; points <- matrix(p,nrow=1)
      for (k in seq_len(max_steps)) {
        d <- direction(p)
        if (anyNA(d)) break
        mid <- p+sign*step*d/2
        d <- direction(mid)
        if (anyNA(d)) break
        next_p <- p+sign*step*d
        if (!inside(next_p) || exists(key(next_p),occupied,inherits=FALSE)) break
        # Stop a closed orbit rather than tracing the same ring repeatedly.
        if (k > 20 && any(rowSums(sweep(points[seq_len(nrow(points)-15),,drop=FALSE],
            2,next_p,"-")^2) < (1.5*step)^2)) break
        points <- rbind(points,next_p); p <- next_p
      }
      points
    }
    backward <- trace(-1); forward <- trace(1)
    points <- rbind(backward[nrow(backward):1,,drop=FALSE],forward[-1,,drop=FALSE])
    if (nrow(points) < 12) next
    paths[[length(paths)+1L]] <- data.frame(x=points[,1],y=points[,2],group=length(paths)+1L)
    for (k in seq_len(nrow(points))) assign(key(points[k,]),TRUE,occupied)
  }
  if (!length(paths)) return(data.frame(x=numeric(),y=numeric(),group=integer()))
  do.call(rbind,paths)
}

weather_circulation_plot <- function(rasters, date, directory) {
  # Plotting stays on the native decoded grid. Pacific-centered coordinates use
  # 120-300 degrees east; do not interpolate across the dateline for this pilot.
  stack <- c(rasters$height500, rasters$u250, rasters$v250)
  data <- terra::as.data.frame(stack, xy = TRUE, na.rm = FALSE)
  names(data) <- c("x", "y", "height500", "u250", "v250")
  latitude <- attr(rasters, "gaussian_latitudes")
  if (length(latitude) != terra::nrow(stack)) stop("True Gaussian latitude coordinates are required.")
  data$y <- rep(latitude, each = terra::ncol(stack))
  edges <- c(90, (head(latitude,-1)+tail(latitude,-1))/2, -90)
  data$ymin <- rep(tail(edges,-1),each=terra::ncol(stack))
  data$ymax <- rep(head(edges,-1),each=terra::ncol(stack))
  data$x <- ifelse(data$x < 120, data$x + 360, data$x)
  data <- data[data$x >= 120 & data$x <= 300 & data$y >= 10 & data$y <= 70, ]
  if (!nrow(data) || any(!is.finite(as.matrix(data[, c("height500","u250","v250")]))))
    stop("Incomplete decoded fields in the pilot domain.")
  data$height_dm <- data$height500 / 10
  data$vector_speed <- sqrt(data$u250^2 + data$v250^2)
  data$xmin <- data$x-terra::res(stack)[1L]/2
  data$xmax <- data$x+terra::res(stack)[1L]/2
  labels <- weather_contour_labels(data)
  flow <- weather_streamlines(data)
  arrows <- do.call(rbind,lapply(split(flow,flow$group),function(line) {
    i <- floor(nrow(line)/2)
    data.frame(x=line$x[i],y=line$y[i],xend=line$x[i+2],yend=line$y[i+2])
  }))
  if (is.null(arrows)) arrows <- data.frame(x=numeric(),y=numeric(),xend=numeric(),yend=numeric())
  wind_breaks <- c(0,40,60,80,100,120,140,160,180,200,Inf)
  wind_labels <- c("<40","40-60","60-80","80-100","100-120","120-140",
    "140-160","160-180","180-200","200+")
  data$wind_band <- cut(data$vector_speed*1.943844,wind_breaks,right=FALSE,labels=wind_labels)
  states <- ggplot2::map_data("state")
  states$x <- states$long+360
  southwest <- states[states$region %in% c("arizona","new mexico"),]
  world <- ggplot2::map_data("world")
  world$x <- ifelse(world$long < 120, world$long + 360, world$long)
  world$piece <- cumsum(c(TRUE, diff(world$group) != 0 | abs(diff(world$x)) > 180))
  background <- function(plot) plot +
    ggplot2::geom_path(data = world, ggplot2::aes(x, lat, group = piece),
      inherit.aes = FALSE, linewidth = .3, colour = "#39464b") +
    ggplot2::geom_path(data=states,ggplot2::aes(x,lat,group=group),
      inherit.aes=FALSE,linewidth=.18,colour="#465459",alpha=.65) +
    ggplot2::geom_path(data=southwest,ggplot2::aes(x,lat,group=group),
      inherit.aes=FALSE,linewidth=1.05,colour="white",alpha=.9) +
    ggplot2::geom_path(data=southwest,ggplot2::aes(x,lat,group=group),
      inherit.aes=FALSE,linewidth=.6,colour="#843b86") +
    ggplot2::coord_quickmap(xlim = c(120, 300), ylim = c(10, 70), expand = FALSE) +
    ggplot2::scale_x_continuous(breaks = seq(120, 300, 30),
      labels = c("120E", "150E", "180", "150W", "120W", "90W", "60W")) +
    ggplot2::labs(x = NULL, y = NULL,
      subtitle = paste(date, "UTC | CORe ensemble mean | eight-sample daily average"),
      caption = paste("Data source: NOAA CPC CORe",
        "Reanalysis, not direct observations | 00-21 UTC samples every three hours",
        "Climate Science Applications Program - University of Arizona", sep = "\n")) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"),
      legend.position = "bottom", legend.title.position="top",
      panel.grid.minor = ggplot2::element_blank())
  height <- background(ggplot2::ggplot(data, ggplot2::aes(x, y)) +
    ggplot2::geom_rect(ggplot2::aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=height_dm),colour=NA) +
    ggplot2::geom_contour(ggplot2::aes(z = height_dm), breaks = seq(420, 630, 6),
      colour = "#263238", linewidth = .3) +
    # Visual reference contours, not thresholds for unusual conditions.
    ggplot2::geom_contour(ggplot2::aes(z = height_dm), breaks = c(588,594),
      colour = "#263238", linewidth = .48) +
    ggplot2::geom_contour(ggplot2::aes(z = height_dm), breaks = seq(420,630,30),
      colour = "#263238", linewidth = .65) +
    ggplot2::geom_label(data=labels,ggplot2::aes(label=label),size=2.6,
      fill=scales::alpha("white",.8),linewidth=0,label.padding=grid::unit(.06,"lines")) +
    # Fixed anchors across seasons: retain contrast in winter and separate
    # the closely spaced high heights that define the summer ridge.
    ggplot2::scale_fill_gradientn(
      colours=c("#24496e","#417bb2","#93bdd9","#d3e6eb","#f5f2df",
        "#f4d487","#edb557","#e89436","#d87526","#bb571e","#913c18"),
      values=scales::rescale(c(480,510,540,558,570,582,588,594,600,606,612),from=c(480,612)),
      name = "500-mb height (dam)", limits = c(480, 612),
      breaks=c(480,510,540,570,582,588,594,600,606,612),
      guide=ggplot2::guide_colourbar(barwidth=grid::unit(20,"cm")),
      oob = scales::squish) + ggplot2::labs(title = "500-mb circulation - absolute heights (6-dam contours)"))
  jet <- background(ggplot2::ggplot(data, ggplot2::aes(x, y)) +
    ggplot2::geom_rect(ggplot2::aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=wind_band),colour=NA,show.legend=TRUE) +
    ggplot2::geom_path(data=flow,ggplot2::aes(group=group),linewidth=.24,colour="#263238",alpha=.8) +
    ggplot2::geom_segment(data = arrows, ggplot2::aes(xend = xend, yend = yend),
      arrow = grid::arrow(length = grid::unit(1.2, "mm")), linewidth = .25) +
    ggplot2::scale_fill_manual(name="Speed of daily-mean 250-mb wind (knots)",drop=FALSE,
      values=setNames(c("#f5f8fa","#d3eef1","#8bd1dd","#3ca5ba","#387f92",
        "#74ad74","#dad76a","#f2ad4e","#dd6541","#9c3564"),wind_labels),
      guide=ggplot2::guide_legend(nrow=1)) +
    ggplot2::labs(title = "250-mb flow - speed of daily-mean wind components"))
  paths <- c(height500 = file.path(directory, "height500.png"), jet250 = file.path(directory, "jet250.png"))
  ggplot2::ggsave(paths[[1L]], height, width = 12, height = 6.8, dpi = 160, bg = "white")
  ggplot2::ggsave(paths[[2L]], jet, width = 12, height = 6.8, dpi = 160, bg = "white")
  paths
}

run_weather_circulation_pilot <- function(dates = as.Date("2023-03-01"),
    output_dir = file.path("data", "diagnostics", "weather-circulation-pilot"),
    refresh = FALSE, render_maps = TRUE) {
  dates <- as.Date(dates)
  if (!length(dates) || length(dates) > 4L || anyNA(dates) || anyDuplicated(dates))
    stop("Choose 1-4 unique pilot dates; no historical backfill.")
  rows <- lapply(seq_along(dates), function(i) {
    date <- dates[i]; started <- proc.time()[["elapsed"]]
    directory <- file.path(output_dir, as.character(date))
    download <- weather_core_download(date, directory, refresh)
    before_decode <- proc.time()[["elapsed"]]
    rasters <- weather_core_decode(download$paths, directory)
    decode_seconds <- proc.time()[["elapsed"]] - before_decode
    before_render <- proc.time()[["elapsed"]]
    if (render_maps) weather_circulation_plot(rasters, date, directory)
    render_seconds <- proc.time()[["elapsed"]] - before_render
    metadata <- download$plan
    metadata$url <- paste0(weather_core_url(date), ".grb")
    metadata$md5 <- unname(tools::md5sum(download$paths))
    utils::write.csv(metadata, file.path(directory, "source-fields.csv"), row.names = FALSE)
    row <- data.frame(date = as.character(date), source = "CORe cloud daily ensemble mean",
      cached = download$cached, requests = download$requests,
      transferred_bytes = download$transferred_bytes, download_seconds = download$download_seconds,
      decode_seconds = decode_seconds, render_seconds = render_seconds,
      total_seconds = proc.time()[["elapsed"]] - started,
      retained_bytes = sum(file.info(list.files(directory, full.names = TRUE))$size, na.rm = TRUE))
    message("CORe pilot ", date, ": ", download$requests, " requests; ", download$transferred_bytes, " bytes.")
    row
  })
  summary <- do.call(rbind, rows)
  utils::write.csv(summary, file.path(output_dir, "pilot-summary.csv"), row.names = FALSE)
  history <- file.path(output_dir, "pilot-runs.csv")
  logged <- cbind(run_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC"), summary)
  if (file.exists(history)) logged <- rbind(utils::read.csv(history), logged)
  utils::write.csv(logged, history, row.names = FALSE)
  message("Local CORe pilot only: no production, baseline build or ERA5 request.")
  invisible(list(summary = summary, output_dir = output_dir))
}

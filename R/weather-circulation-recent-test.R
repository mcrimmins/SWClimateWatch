# Bounded local readiness test; never publishes or changes production settings.
weather_core_probe_response <- function(status, body, date) {
  if (status == 404L) return(list(status="NOT_POSTED",note="Daily index not posted."))
  if (status != 200L) return(list(status="ERROR",note=paste("HTTP",status)))
  tryCatch({
    lines <- trimws(strsplit(rawToChar(body),"\n",fixed=TRUE)[[1L]])
    weather_core_plan(lines,date)
    list(status="AVAILABLE",note="Three required complete daily fields indexed.")
  },error=function(e) list(status="INVALID_INDEX",note=conditionMessage(e)))
}

check_weather_core_recent <- function(today=Sys.Date(),lookback_days=7L) {
  today <- as.Date(today)
  if (length(today)!=1L || is.na(today) || length(lookback_days)!=1L ||
      !is.finite(lookback_days) || lookback_days<1 || lookback_days>10 ||
      lookback_days!=floor(lookback_days)) stop("Choose one date and 1-10 lookback days.")
  rows <- lapply(seq_len(lookback_days),function(age) {
    date <- today-age; started <- proc.time()[["elapsed"]]; bytes <- 0L
    result <- tryCatch({
      request <- weather_core_request(paste0(weather_core_url(date),".idx")) |>
        httr2::req_error(is_error=function(resp) FALSE)
      response <- httr2::req_perform(request)
      body <- httr2::resp_body_raw(response); bytes <- length(body)
      weather_core_probe_response(httr2::resp_status(response),body,date)
    },error=function(e) list(status="ERROR",note=conditionMessage(e)))
    message("CORe availability ",date,": ",result$status)
    data.frame(date=as.character(date),age_days=age,status=result$status,
      transferred_bytes=bytes,seconds=proc.time()[["elapsed"]]-started,note=result$note)
  })
  do.call(rbind,rows)
}

run_weather_circulation_recent_test <- function(today=Sys.Date(),lookback_days=7L,
    sample_days=3L,output_dir=file.path("data","diagnostics","weather-circulation-recent-test")) {
  if (length(sample_days)!=1L || !is.finite(sample_days) || sample_days<1 ||
      sample_days>4 || sample_days!=floor(sample_days)) stop("Choose 1-4 sample days.")
  started <- proc.time()[["elapsed"]]
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  availability <- check_weather_core_recent(today,lookback_days)
  utils::write.csv(availability,file.path(output_dir,"availability.csv"),row.names=FALSE)
  dates <- as.Date(head(availability$date[availability$status=="AVAILABLE"],sample_days))
  if (!length(dates)) stop("No complete recent indexes found; see availability.csv. No maps built.")
  first <- run_weather_circulation_pilot(sort(dates),output_dir=output_dir)
  # Verify a second pass requires no data requests. Rendering is deliberately
  # disabled here; the pilot has no map-output skip cache yet.
  cached <- run_weather_circulation_pilot(sort(dates),output_dir=output_dir,render_maps=FALSE)
  utils::write.csv(first$summary,file.path(output_dir,"first-pass.csv"),row.names=FALSE)
  utils::write.csv(cached$summary,file.path(output_dir,"cache-check.csv"),row.names=FALSE)
  summary <- data.frame(checked_on=as.character(as.Date(today)),
    dates_checked=nrow(availability),dates_available=sum(availability$status=="AVAILABLE"),
    probe_errors=sum(availability$status %in% c("ERROR","INVALID_INDEX")),
    latest_available=as.character(max(dates)),lag_days=as.integer(as.Date(today)-max(dates)),
    dates_built=length(dates),maps_built=length(dates)*2L,
    sequence_has_gaps=length(dates)>1L && any(diff(sort(dates))!=1),
    availability_requests=nrow(availability),
    availability_bytes=sum(availability$transferred_bytes),
    first_pass_requests=sum(first$summary$requests),first_pass_bytes=sum(first$summary$transferred_bytes),
    first_pass_seconds=sum(first$summary$total_seconds),
    cache_check_requests=sum(cached$summary$requests),cache_check_seconds=sum(cached$summary$total_seconds),
    cache_check_pass=all(cached$summary$cached) && sum(cached$summary$requests)==0,
    total_seconds=proc.time()[["elapsed"]]-started)
  utils::write.csv(summary,file.path(output_dir,"recent-test-summary.csv"),row.names=FALSE)
  cards <- vapply(as.character(sort(dates)),function(date) paste0(
    '<section><h2>',date,' UTC</h2><div class="pair">',
    '<a href="',date,'/height500.png"><img alt="500 mb heights" src="',date,'/height500.png"></a>',
    '<a href="',date,'/jet250.png"><img alt="250 mb flow" src="',date,'/jet250.png"></a></div></section>'),character(1))
  writeLines(c('<!doctype html><html lang="en"><meta charset="utf-8"><title>CORe recent-date test</title>',
    '<style>body{font:16px system-ui;margin:24px;background:#f2f5f6;color:#22313a}.pair{display:grid;grid-template-columns:1fr 1fr;gap:12px}img{width:100%}section{margin:28px 0}@media(max-width:900px){.pair{grid-template-columns:1fr}}</style>',
    '<h1>CORe circulation: local recent-date test</h1>',
    '<p>Daily means, not forecasts. Click a map for full size. Absolute heights, no anomaly baseline. Streamlines show mean flow, not storm tracks.</p>',
    cards,'</html>'),file.path(output_dir,"index.html"))
  print(summary,row.names=FALSE)
  message("Local test only; no site rendering, S3 sync or production changes.")
  invisible(list(summary=summary,availability=availability,first_pass=first$summary,
    cache_check=cached$summary,preview=file.path(output_dir,"index.html")))
}

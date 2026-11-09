# Fictional, deterministic editorial cases. Never reads operational climate caches.
synopsis_seasonal_cases <- function() {
  cases <- data.frame(
    id = c("winter-cold", "winter-quiet", "spring-cold", "spring-dry", "summer-heat",
      "monsoon-wet", "monsoon-localized", "monsoon-heat", "fall-cold", "october-rollover",
      "opposing-states", "missing-support", "leap-day", "ordinary-hot-day"),
    date = c("2026-02-15", "2026-02-20", "2026-04-15", "2026-04-30", "2026-06-10",
      "2026-07-20", "2026-08-15", "2026-08-30", "2026-10-15", "2026-10-01",
      "2026-11-15", "2026-12-15", "2024-02-29", "2026-07-10"),
    label = c("Winter cold spell", "Quiet winter week; fewer freeze nights", "Late spring cold spell",
      "Quiet spring week; longer dry spell", "Early summer heat", "Widespread monsoon precipitation",
      "Localized monsoon storm; small regional average", "Hot monsoon week", "Fall cold spell",
      "October 1: rolling week crosses water-year boundary", "Opposing AZ and NM temperatures",
      "Missing regional evidence and insufficient station history", "Leap day with limited normal support",
      "Large absolute temperature, ordinary historical standing"),
    rain = c(.03,.01,.02,.01,.01,.85,.05,.01,.01,.04,.01,NA,.02,.02),
    temp = c(-6,0,-4,0,5,0,0,5,-4,0,0,NA,-5,0),
    metric = c("coldest_night","freeze_nights_anomaly","coldest_night","longest_dry_spell",
      "hottest_day","max_3day_pcpn","max_daily_pcpn","hottest_day","coldest_night","",
      "","max_daily_pcpn","coldest_night","hottest_day"),
    expected_focus = c("cold","longer_term","cold","longer_term","heat","rainfall","rainfall",
      "heat","cold","longer_term","mixed","uncertain","cold","longer_term"),
    expected_metric = c("coldest_night","freeze_nights_anomaly","coldest_night","longest_dry_spell",
      "hottest_day","max_3day_pcpn","max_daily_pcpn","hottest_day","coldest_night","",
      "","","coldest_night",""), stringsAsFactors = FALSE)
  cases$regional_case <- cases$expected_kind <- cases$expected_tone <- ""
  extra <- cases[rep(10L, 10L), ]
  extra$id <- extra$regional_case <- c("persistent-warm-days", "persistent-cold-nights", "rank-improving", "rank-declining",
    "stations-wet", "stations-dry", "stations-warm", "stations-cold", "competing-highlights", "withheld-highlights")
  extra$date <- c("2026-07-20", "2026-02-15", "2026-08-20", "2026-05-20", "2026-08-20", "2026-05-20",
    "2026-07-20", "2026-02-15", "2026-08-20", "2026-11-15")
  extra$label <- c("Persistence: widespread warm days in the past month", "Persistence: widespread cold nights in the past month",
    "Transition: improving 30-day precipitation ranks", "Transition: declining 30-day precipitation ranks",
    "Station agreement: wet 30-day totals", "Station agreement: dry 30-day totals",
    "Station agreement: warm 30-day temperatures", "Station agreement: cold 30-day temperatures",
    "Competing signals: station agreement wins; other options remain available", "Withholding: small areas and insufficient station support")
  extra$expected_kind <- c("persistence", "persistence", "transition", "transition", rep("corroboration", 5L), "")
  extra$expected_tone <- c("warm", "cold", "wet", "dry", "wet", "dry", "warm", "cold", "wet", "")
  rbind(cases, extra)
}

synopsis_seasonal_regional_fixture <- function(case, evidence) {
  date <- as.Date(case$date); id <- case$regional_case
  start <- as.character(date - 29L); end <- as.character(date)
  grid <- function(product, metric, value) data.frame(fact_id = paste0("synthetic-regional:", id, ":", metric),
    product = product, region = "AZNM", metric = metric, value = value, status = "AVAILABLE_CACHED", coverage = 1,
    period_start = start, period_end = end, comparison_date = as.character(date - 14L),
    source_path = paste0("synthetic:", id), source_md5 = "synthetic", link = paste0("pages/products/", product, ".html"), note = "Fictional validation input")
  station <- function(variable, tail, count = 24L, eligible = 30L) data.frame(
    fact_id = paste0("synthetic-network:", id), region = "AZNM", period = "30day", variable = variable, tail = tail,
    count = count, eligible = eligible, percent = 100*count/eligible, status = "AVAILABLE_CACHED",
    period_start = start, period_end = end, link = "pages/station-conditions.html", source_path = paste0("synthetic:", id), source_md5 = "synthetic")
  grids <- data.frame(); network <- data.frame()
  if (id %in% c("persistent-warm-days", "competing-highlights", "withheld-highlights"))
    grids <- grid("maxt_extreme_warm_count_30day", "area_extreme_days", if (id == "withheld-highlights") 19 else 55)
  if (id == "persistent-cold-nights") grids <- grid("mint_extreme_cold_count_30day", "area_extreme_days", 60)
  if (id %in% c("rank-improving", "rank-declining", "competing-highlights", "withheld-highlights")) {
    x <- grid("pcpn_percentile_change_30day_14day", if (id == "rank-declining") "area_rank_decreased" else "area_rank_increased",
      if (id == "withheld-highlights") 19 else 65)
    grids <- if (nrow(grids)) rbind(grids, x) else x
  }
  if (grepl("^stations-", id) || id %in% c("competing-highlights", "withheld-highlights")) {
    network <- station(if (id %in% c("stations-warm", "stations-cold")) "tmean" else "pcpn",
      if (id %in% c("stations-dry", "stations-cold")) "low" else "high")
    if (id == "withheld-highlights") {
      network$count <- network$eligible <- 3L; network$percent <- 100
      network$status <- "INSUFFICIENT_STATIONS"
    }
  }
  # Monthly context is consistent with the example's monthly signal, while the
  # quiet seven-day inputs demonstrate why longer-term context can be useful.
  if (id %in% c("persistent-warm-days", "stations-warm")) evidence$facts$value[evidence$facts$metric == "mean_departure"] <- 4
  if (id %in% c("persistent-cold-nights", "stations-cold")) evidence$facts$value[evidence$facts$metric == "mean_departure"] <- -4
  if (id %in% c("stations-dry", "rank-declining")) {
    evidence$facts$value[evidence$facts$metric == "area_below_lower_percentile"] <- 70
    evidence$facts$value[evidence$facts$metric == "area_above_upper_percentile"] <- 5
  }
  if (id %in% c("stations-wet", "rank-improving", "competing-highlights")) {
    evidence$facts$value[evidence$facts$metric == "area_below_lower_percentile"] <- 5
    evidence$facts$value[evidence$facts$metric == "area_above_upper_percentile"] <- 70
  }
  evidence$regional_highlights <- list(normal_reference = "1991-2020", centered_window_days = 5,
    grids = grids, stations = list(facts = network, members = data.frame(), status = "SYNTHETIC_VALIDATION"))
  evidence
}

synopsis_seasonal_fixture <- function(case, config) {
  date <- as.Date(case$date)
  specs <- synopsis_grid_specs("synthetic-unused", date)
  rows <- list()
  for (i in seq_len(nrow(specs))) for (region in c("AZNM", "AZ", "NM")) {
    spec <- specs[i, ]
    metrics <- switch(spec$type, rain = c("mean", "area_at_least_rain_threshold"),
      temperature = "mean_departure", percentile = c("area_below_lower_percentile", "area_above_upper_percentile",
        "area_below_very_low_percentile", "area_above_very_high_percentile"))
    for (metric in metrics) rows[[length(rows) + 1L]] <- data.frame(
      fact_id = paste(spec$id, region, metric, sep = ":"), product = spec$id, region = region,
      metric = metric, value = if (metric == "mean") 2 else if (metric == "mean_departure") 1 else 20,
      units = if (grepl("^area_", metric)) "percent of valid region area" else if (spec$type == "temperature") "degreeF departure" else "inch",
      threshold = switch(metric, area_below_lower_percentile = 33, area_above_upper_percentile = 67,
        area_below_very_low_percentile = 10, area_above_very_high_percentile = 90,
        area_at_least_rain_threshold = .1, NA_real_),
      period_start = spec$start, period_end = spec$end, reference = spec$reference,
      coverage = 1, valid_area_km2 = 1, total_area_km2 = 1, status = "AVAILABLE_CACHED",
      note = "Fictional validation input", source_path = paste0("synthetic:", case$id), source_md5 = "synthetic",
      link = spec$link, mask_version = "synthetic-validation-v1", stringsAsFactors = FALSE)
  }
  facts <- do.call(rbind, rows)
  recent <- facts[facts$product %in% c("pcpn_total_30day", "tmean_departure_30day"), ]
  recent$product <- sub("30day", "07day", recent$product)
  recent$fact_id <- sub("30day", "07day", recent$fact_id)
  recent$link <- "pages/daily-explorer.html"
  recent$period_start <- as.character(date - 6L)
  recent$value[recent$metric == "mean"] <- case$rain
  recent$value[recent$metric == "mean_departure"] <- case$temp
  if (case$id == "opposing-states") recent$value[recent$metric == "mean_departure"] <- c(0,5,-5)
  if (case$id == "missing-support") {
    recent$status <- "LOW_COVERAGE"; recent$value <- NA_real_; recent$coverage <- .7
  }
  # At rollover the accumulated water year contains only October 1.
  if (case$id == "october-rollover") facts$value[facts$product == "pcpn_water_year_total" & facts$metric == "mean"] <- .02
  candidate <- data.frame(fact_id = paste0("synthetic-station:", case$id), uid = "synthetic-A",
    window_days = 7L, name = "Fictional review station", state = "NM", metric = case$metric,
    family = if (case$metric %in% c("max_daily_pcpn", "max_3day_pcpn")) "rainfall" else if (case$metric == "longest_dry_spell") "dryness" else "temperature",
    value = switch(case$metric, max_daily_pcpn = 1.8, max_3day_pcpn = 3.2, hottest_day = 115,
      coldest_night = 12, freeze_nights_anomaly = -8, longest_dry_spell = 24, 0),
    units = if (case$metric %in% c("max_daily_pcpn", "max_3day_pcpn")) "inch" else if (case$metric == "longest_dry_spell") "days" else if (case$metric == "freeze_nights_anomaly") "nights departure" else "degreeF",
    period_start = as.character(date - 6L), period_end = as.character(date),
    event_start = as.character(date), event_end = as.character(date), observed = 60, normal = 68,
    sample_years = 23, reference = "1991-2020", caution_codes = "", source_path = paste0("synthetic:", case$id),
    source_md5 = "synthetic", link = "pages/station-conditions.html", context_status = "SUPPORTED",
    historical_rank = 2, historical_n = 40, historical_first_year = as.integer(format(date, "%Y")) - 60L,
    historical_last_year = as.integer(format(date, "%Y")) - 1L, historical_ties = 1,
    rank_direction = if (case$metric == "coldest_night") "lowest" else "highest",
    historical_percentile = if (case$metric == "coldest_night") 2.5 else 97.5, unusual_percentile = 97.5,
    context_normal = NA_real_, context_normal_years = 20, peak_anomaly = NA_real_,
    reference_signature = "synthetic", context_reason = "Fictional validation input", stringsAsFactors = FALSE)
  if (case$metric == "max_3day_pcpn") candidate$event_start <- as.character(date - 2L)
  if (case$id == "ordinary-hot-day") candidate$unusual_percentile <- candidate$historical_percentile <- 70
  if (case$id == "missing-support") {
    candidate$context_status <- "INSUFFICIENT_REFERENCE"; candidate$historical_n <- 10
    candidate$unusual_percentile <- NA_real_
  }
  if (case$id == "leap-day") {
    candidate$historical_n <- 30; candidate$context_normal_years <- 7
  }
  empty <- candidate[FALSE, ]
  week <- if (nzchar(case$metric) && !case$metric %in% c("freeze_nights_anomaly", "longest_dry_spell")) candidate else empty
  long <- if (case$metric %in% c("freeze_nights_anomaly", "longest_dry_spell")) candidate else empty
  if (nrow(long)) {
    long$window_days <- 30L; long$period_start <- as.character(date - 29L)
    long$event_start <- as.character(date - 23L)
    if (case$metric == "freeze_nights_anomaly") {
      long$context_status <- "SEASONAL_DEPARTURE"
      long$event_start <- long$period_start <- specs$start[4L]
    }
  }
  evidence <- list(data_kind = "synthetic_validation", scenario_label = case$label,
    snapshot_date = as.character(date), generated_utc = "Synthetic scenario", snapshot_age_days = 1L,
    configuration = config, signature = paste0("synthetic:", case$id), season = synopsis_season(date, config),
    facts = facts, recent = list(facts = recent, days = data.frame(), signature = "synthetic"),
    snow = list(active = format(date, "%m") %in% c("10","11","12","01","02","03","04","05"),
      regional_metrics = "DEFERRED_MASK_DEFINITION"),
    station_extremes = list(candidates = long), station_week = list(candidates = week))
  if (!is.null(case$regional_case) && nzchar(case$regional_case)) evidence <- synopsis_seasonal_regional_fixture(case, evidence)
  evidence
}

review_conditions_synopsis_seasons <- function(root = ".", output_dir = file.path(root,
    "data/diagnostics/conditions-synopsis/seasonal-review")) {
  config <- synopsis_config(file.path(root, "config/conditions-synopsis.yml"))
  cases <- synopsis_seasonal_cases()
  results <- lapply(seq_len(nrow(cases)), function(i) {
    case <- cases[i, ]; evidence <- synopsis_seasonal_fixture(case, config)
    path <- file.path(output_dir, case$id)
    draft <- build_conditions_synopsis_draft(evidence, root, path, track_preview = FALSE, show_review_candidates = TRUE)
    jsonlite::write_json(evidence, file.path(path, "evidence.json"), dataframe = "rows",
      auto_unbox = TRUE, na = "null", pretty = TRUE)
    highlights <- attr(draft$blocks, "highlights")
    selected <- draft$station_extremes$selected
    prose <- vapply(draft$blocks, function(b) b$text, character(1))
    weekly <- Filter(function(b) b$section == "Past 7 days", draft$blocks)
    source_ids <- c(evidence$facts$fact_id, evidence$recent$facts$fact_id,
      evidence$station_week$candidates$fact_id, evidence$station_extremes$candidates$fact_id,
      evidence$regional_highlights$grids$fact_id, evidence$regional_highlights$stations$facts$fact_id)
    monthly <- Filter(function(b) b$section == "Past 30 days", draft$blocks)
    supplemental <- Filter(function(b) !is.null(b$kind), monthly)
    selected_kind <- if (length(supplemental)) supplemental[[1L]]$kind else ""
    checks <- c(focus = highlights$profile$mode == case$expected_focus,
      station = if (nzchar(case$expected_metric)) case$expected_metric %in% selected$metric else nrow(selected) == 0L,
      budget = nrow(selected) <= 2L && !anyDuplicated(selected$uid),
      weekly_budget = length(weekly) <= 3L,
      monthly_budget = sum(vapply(draft$blocks, function(b) b$section == "Past 30 days", logical(1))) <= 3L,
      yearly_budget = sum(vapply(draft$blocks, function(b) b$section == "Water year so far", logical(1))) <= 3L,
      sources = all(unlist(lapply(draft$blocks, function(b) b$fact_ids)) %in% source_ids),
      readable_dates = !any(grepl("[0-9]{4}-[0-9]{2}-[0-9]{2}", prose)),
      synthetic_label = any(grepl("SYNTHETIC VALIDATION", readLines(draft$path))),
      history_untouched = !file.exists(file.path(path, "preview-state.rds")))
    if (nzchar(case$regional_case)) {
      checks <- c(checks, regional_selection = identical(selected_kind, case$expected_kind))
      if (nzchar(case$expected_kind)) checks <- c(checks,
        regional_color = identical(supplemental[[1L]]$emphasis[[1L]]$tone, case$expected_tone))
      if (case$id == "competing-highlights") checks <- c(checks,
        alternatives_retained = length(attr(draft$blocks, "regional_candidates")) == 3L,
        distinct_third = length(monthly) == 3L && monthly[[3L]]$kind == "transition")
    }
    if (case$id == "monsoon-localized") checks <- c(checks, localized_lead = grepl("Fictional review station", weekly[[1]]$text))
    if (case$id == "opposing-states") checks <- c(checks, contrast_lead = grepl("Mean temperatures contrasted", weekly[[1]]$text))
    if (case$expected_focus %in% c("heat", "cold")) checks <- c(checks, temperature_lead = grepl("Mean temperature", weekly[[1]]$text))
    if (case$id == "october-rollover") checks <- c(checks,
      rolling_week = all(evidence$recent$facts$period_start == "2026-09-25"),
      new_water_year = all(evidence$facts$period_start[grepl("water_year", evidence$facts$product)] == "2026-10-01"))
    data.frame(id = case$id, label = case$label, snapshot_date = case$date, expected_focus = case$expected_focus,
      actual_focus = highlights$profile$mode, selected_metric = paste(selected$metric, collapse = ";"), monthly_highlight = selected_kind,
      status = if (all(checks)) "PASS_TEMPLATE" else "FAIL",
      failed_checks = paste(names(checks)[!checks], collapse = ";"),
      snow_interpretation = if (evidence$snow$active) "SEPARATE_SNOW_REVIEW" else "INACTIVE", stringsAsFactors = FALSE)
  })
  summary <- do.call(rbind, results)
  utils::write.csv(summary, file.path(output_dir, "summary.csv"), row.names = FALSE)
  html <- c('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Synopsis seasonal review</title>',
    '<style>body{font:16px/1.5 system-ui;color:#26383f;max-width:1100px;margin:30px auto;padding:20px}td,th{text-align:left;padding:10px;border-bottom:1px solid #ddd}a{color:#08718b}.note{padding:14px;background:#fff1df}table{width:100%}</style>',
    '<h1>Synopsis seasonal review</h1><p class="note"><strong>SYNTHETIC VALIDATION: fictional inputs, not observations.</strong> These cases test wording and editorial selection. They do not validate historical weather events or snow interpretation. Regional snow metrics remain pending.</p>')
  if (file.exists(file.path(dirname(output_dir), "synopsis.html"))) html <- c(html,
    '<p>Separate observational preview: <a href="../synopsis.html">Current cached-data synopsis</a>.</p>')
  html <- c(html, '<p>The first 14 cases cover seasonal editorial focus. The additional 10 cover monthly warm/cold persistence, improving/declining precipitation rank, wet/dry/warm/cold station counts, competing highlights and withholding unsupported highlights.</p>',
    '<table><thead><tr><th>Scenario</th><th>Weekly focus</th><th>Monthly highlight</th><th>Template check</th><th>Snow interpretation</th></tr></thead><tbody>',
    vapply(seq_len(nrow(summary)), function(i) paste0('<tr><td><a href="', summary$id[i], '/synopsis.html">',
      summary$label[i], '</a></td><td>', summary$actual_focus[i], '</td><td>', summary$monthly_highlight[i], '</td><td>', summary$status[i],
      if (nzchar(summary$failed_checks[i])) paste0(": ", summary$failed_checks[i]) else "", '</td><td>', summary$snow_interpretation[i], '</td></tr>'), character(1)),
    '</tbody></table></html>')
  writeLines(html, file.path(output_dir, "index.html"), useBytes = TRUE)
  message(sum(summary$status == "PASS_TEMPLATE"), "/", nrow(summary), " seasonal template cases passed; snow-specific cases have a separate review gallery.")
  invisible(list(summary = summary, path = file.path(output_dir, "index.html")))
}


# Snow-specific fictional review cases complement the existing 24 weather cases.
review_conditions_synopsis_snow <- function(root=".",output_dir=file.path(root,"data/diagnostics/conditions-synopsis/snow-review")) {
  config<-synopsis_config(file.path(root,"config/conditions-synopsis.yml"))
  cases<-data.frame(id=c("winter-deficit","winter-surplus","spring-loss","fall-new-snow","winter-missing","small-reference","summer-inactive"),
    date=c("2026-02-15","2026-02-15","2026-04-15","2026-10-15","2026-02-15","2026-04-15","2026-07-15"),
    observed=c(.1,4,1,1,NA,.1,1),median=c(2,2,2,0,2,2,2),previous=c(.1,2,3,0,2,.1,0),
    area=c(3000,3000,3000,3000,3000,300,3000),expected=c("storage","change;storage","change;storage","change","","",""))
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  results<-lapply(seq_len(nrow(cases)),function(i) {
    case<-cases[i,]; d<-as.Date(case$date)
    base<-synopsis_seasonal_cases()[if(format(d,"%m") %in% c("02"))2L else if(format(d,"%m")=="04")4L else if(format(d,"%m")=="10")10L else 14L,]
    base$date<-case$date; base$id<-case$id;base$label<-paste("Fictional snow review:",case$id)
    e<-synopsis_seasonal_fixture(base,config)
    stats<-synopsis_snow_stats(rep(case$observed,3),rep(case$median,3),rep(21,3),rep(case$previous,3),rep(case$area/3,3),config)
    rows<-list()
    for(kind in names(stats)) {
      z<-stats[[kind]]
      for(metric in names(z$values))rows[[length(rows)+1L]]<-data.frame(fact_id=paste("snow",kind,metric,sep=":"),product=paste0("snow_",kind),
        region="AZNM",metric=metric,value=unname(z$values[[metric]]),units=if(grepl("percent",metric))"percent" else "inches SWE",
        period_start=as.character(if(kind=="change")d-7L else d),period_end=as.character(d),reference="Fictional WY2005–WY2025 reference",
        denominator=if(kind=="storage")"Normally snowy cells; median >=1 inch, >=18 years" else "Normally snowy or snow at either endpoint",
        eligible_area_km2=z$area_km2,coverage=z$coverage,status=z$status,link="pages/snow-conditions.html")
    }
    e$snow_context<-list(active=e$snow$active,facts=if(length(rows))do.call(rbind,rows) else data.frame())
    snow<-synopsis_snow_blocks(e)
    kinds<-sort(vapply(snow,function(b)sub("snow_","",b$kind,fixed=TRUE),character(1)))
    expected<-if(nzchar(case$expected))sort(strsplit(case$expected,";",fixed=TRUE)[[1L]]) else character()
    draft<-build_conditions_synopsis_draft(e,root,file.path(output_dir,case$id))
    shown<-Filter(function(b)!is.null(b$kind)&&startsWith(b$kind,"snow_"),draft$blocks)
    data.frame(case=case$id,status=if(identical(kinds,expected))"PASS" else "FAIL",available_snow=paste(kinds,collapse=";"),
      selected_snow=length(shown),page=paste0(case$id,"/synopsis.html"))
  })
  summary<-do.call(rbind,results)
  write.csv(summary,file.path(output_dir,"summary.csv"),row.names=FALSE)
  html<-c('<!doctype html><html><head><meta charset="utf-8"><title>Snow synopsis review</title></head><body><h1>Snow synopsis review</h1><p>Fictional validation cases, not observations. Each bullet links to dated supporting values.</p><ul>',
    paste0('<li><a href="',summary$page,'">',summary$case,'</a> — ',summary$status,'</li>'),'</ul></body></html>')
  writeLines(html,file.path(output_dir,"index.html"),useBytes=TRUE)
  invisible(list(summary=summary,path=file.path(output_dir,"index.html")))
}

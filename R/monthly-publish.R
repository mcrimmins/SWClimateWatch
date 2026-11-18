# Opt-in monthly calculations within the existing daily scheduler.
swc_monthly_maps_enabled <- function() {
  value <- tolower(trimws(Sys.getenv("SWC_MONTHLY_MAPS", "false")))
  if (!value %in% c("", "false", "0", "no", "off", "true", "1", "yes", "on"))
    stop("SWC_MONTHLY_MAPS must be true or false.")
  value %in% c("true", "1", "yes", "on")
}

swc_monthly_retained_release <- function(site_dir = "site") {
  tryCatch({
    checked <- validate_prism_monthly_publication(site_dir = site_dir,
      report_dir = "data/diagnostics/prism-monthly-update/retained-release")
    if (checked$summary$status != "PASS") return(list(valid = FALSE))
    doc <- xml2::read_html(file.path(site_dir, "pages/monthly-climate.qmd"))
    end <- xml2::xml_attr(xml2::xml_find_first(doc, '//*[@data-monthly-end]'), "data-monthly-end")
    src <- xml2::xml_attr(xml2::xml_find_first(doc, '//img[@data-monthly-map]'), "src")
    manifest <- jsonlite::read_json(file.path(site_dir, "pages", dirname(src), "manifest.json"), simplifyVector = TRUE)
    jobs <- monthly_site_products(end, "data/diagnostics/prism-monthly-ranking-pilots", "data/diagnostics/prism-monthly-spi-pilots")
    hashes <- manifest$products$md5[match(paste(jobs$family, jobs$duration),
      paste(manifest$products$family, manifest$products$duration))]
    matches <- all(file.exists(jobs$source)) && identical(unname(tools::md5sum(jobs$source)), hashes)
    list(valid = TRUE, end_month = end, matches_latest = matches)
  }, error = function(e) list(valid = FALSE, note = conditionMessage(e)))
}

swc_monthly_target <- function(today) format(as.Date(format(as.Date(today), "%Y-%m-01")) - 1L, "%Y-%m")

swc_monthly_publish_log <- function(result, path) {
  row <- data.frame(checked_utc = format(Sys.time(), tz="UTC", usetz=TRUE),
    status = result$status, target_month = result$target_month, published_month = result$published_month,
    requests = result$requests, changed_inputs = result$changed_inputs, built = result$built,
    reused = result$reused, elapsed_seconds = result$elapsed_seconds,
    publication_ready = result$publication_ready, needs_attention = result$needs_attention, note = result$note)
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  write.table(row,path,sep=",",row.names=FALSE,col.names=!file.exists(path)||file.info(path)$size==0,
    append=file.exists(path)&&file.info(path)$size>0,qmethod="double")
}

swc_daily_publish_update_monthly <- function(today=Sys.Date(),
    enabled=swc_monthly_maps_enabled(),
    .load=function() { source("scripts/load-prism-monthly.R"); source("R/prism-monthly-site.R") },
    .run=function(today) run_prism_monthly_update(today=today),
    .stage=function(end) stage_prism_monthly_site(end=end),
    .retained=swc_monthly_retained_release,
    .seed_exists=function() file.exists(file.path(prism_monthly_cache_dir(),"manifest.csv")),
    log_path="data/diagnostics/prism-monthly-update/daily-publish.csv") {
  if (!isTRUE(enabled)) return(list(status="DISABLED"))
  started <- proc.time()[["elapsed"]]
  today <- as.Date(today)
  if(length(today)!=1L||is.na(today)) stop("Expected one monthly run date.")
  target <- swc_monthly_target(today)
  result <- list(status="FAILED",target_month=target,published_month=NA_character_,requests=0L,
    changed_inputs=0L,built=0L,reused=0L,publication_ready=FALSE,needs_attention=FALSE,note="")
  .load()
  held <- .retained()
  result <- tryCatch({
    if (!.seed_exists()) stop("Monthly input manifest missing; transfer the monthly cache before enabling automatic updates.")
    update <- .run(today)
    s <- update$summary
    allowed <- c("COMPLETE","ALREADY_COMPLETE","SKIPPED_OUTSIDE_WINDOW","PENDING_DOWNLOAD","PENDING_PRODUCTS","FAILED")
    if(!is.data.frame(s)||nrow(s)!=1L||!s$status %in% allowed || !identical(as.character(s$target_month),target))
      stop("Monthly updater returned an invalid summary.")
    counts <- c("requests_attempted","changed_inputs","products_built","products_reused")
    if(!all(vapply(counts,function(n) is.numeric(s[[n]])&&length(s[[n]])==1L&&is.finite(s[[n]])&&s[[n]]>=0,logical(1))))
      stop("Monthly updater returned invalid counts.")
    result$status <- s$status; result$requests <- s$requests_attempted
    result$changed_inputs <- s$changed_inputs; result$built <- s$products_built; result$reused <- s$products_reused
    result$note <- if("note" %in% names(s)) as.character(s$note) else ""
    if (s$status %in% c("COMPLETE","ALREADY_COMPLETE")) {
      if (s$status=="COMPLETE" || !isTRUE(held$valid) || !identical(held$end_month,target) || !isTRUE(held$matches_latest)) {
        .stage(target)
        held <- .retained()
        if(!isTRUE(held$valid)||!identical(held$end_month,target)||!isTRUE(held$matches_latest)) stop("New monthly release failed source publication checks.")
      }
    }
    result
  },error=function(e) { result$status <- "FAILED"; result$note <- conditionMessage(e); result })
  # An unsuccessful refresh leaves the immutable, previously staged release in place.
  # Recheck it rather than trusting the earlier assessment after a staging error.
  if(result$status=="FAILED") held <- .retained()
  result$publication_ready <- isTRUE(held$valid)
  result$published_month <- if(isTRUE(held$valid)) held$end_month else NA_character_
  overdue <- as.integer(format(today,"%d")) > 5L &&
    (is.na(result$published_month)||result$published_month < target)
  result$needs_attention <- result$status %in% c("FAILED","PENDING_DOWNLOAD","PENDING_PRODUCTS") || overdue || !result$publication_ready
  if(overdue) result$note <- paste(trimws(result$note),"Monthly cycle overdue; automatic request window ended. Run a manual catch-up.")
  if(!result$publication_ready) result$note <- paste(trimws(result$note),"No verified retained monthly release is available; publication must stop.")
  result$note <- trimws(result$note)
  result$elapsed_seconds <- round(proc.time()[["elapsed"]]-started,3)
  if(!is.null(log_path)) swc_monthly_publish_log(result,log_path)
  result
}

swc_monthly_summary_line <- function(monthly) {
  if(!is.list(monthly)||identical(monthly$status,"DISABLED")) return(character())
  label <- if(length(monthly$published_month)==1L&&!is.na(monthly$published_month))
    format(as.Date(paste0(monthly$published_month,"-01")),"%B %Y") else "unavailable"
  detail <- switch(monthly$status,
    COMPLETE=sprintf("%d checked, %d changed; %d built, %d reused",monthly$requests,monthly$changed_inputs,monthly$built,monthly$reused),
    ALREADY_COMPLETE="cycle already complete; no new requests",
    SKIPPED_OUTSIDE_WINDOW="outside update window; retained maps",
    PENDING_DOWNLOAD="downloads pending; retained maps",
    PENDING_PRODUCTS="map builds pending; retained maps",
    FAILED="update failed; retained maps", "status unknown")
  paste0("Monthly Climate: through ",label,"; ",detail,
    " (",swc_publish_elapsed(monthly$elapsed_seconds),").",
    if(isTRUE(monthly$needs_attention)) paste0(" Attention: ",monthly$note) else "")
}

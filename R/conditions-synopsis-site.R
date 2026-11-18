# Template publication only. Does not source AI modules or make API requests.
synopsis_publication_paths <- function(destination, root = ".") {
  key <- substr(digest::digest(destination, algo = "sha256"), 1L, 12L)
  directory <- file.path(root, "data/diagnostics/conditions-synopsis/publication", key)
  list(directory = directory, success = file.path(directory, "last-success.rds"), pending = file.path(directory, "pending.rds"))
}

synopsis_site_context <- function(root) {
  context <- new.env(parent = globalenv())
  for (file in c("config.R", "acis-prism.R", "process-prism.R", "build-current-prism-maps.R",
      "conditions-synopsis-evidence.R", "conditions-synopsis-template.R", "conditions-synopsis-regional-highlights.R"))
    sys.source(file.path(root, "R", file), envir = context)
  context
}

stage_conditions_synopsis <- function(root = ".", destination = "local-preview", today = Sys.Date(), builder = NULL,
    context_loader = synopsis_site_context) {
  paths <- synopsis_publication_paths(destination, root)
  dir.create(paths$directory, recursive = TRUE, showWarnings = FALSE)
  context <- context_loader(root)
  if (is.null(builder)) builder <- function() context$build_conditions_synopsis_evidence(root = root, today = today)
  prior <- if (file.exists(paths$success)) tryCatch(readRDS(paths$success), error = function(e) NULL) else NULL
  status <- "READY"; note <- ""; date <- NA_character_; evidence <- NULL; draft <- NULL
  tryCatch({
    evidence <- builder(); date <- evidence$snapshot_date
    if (!is.null(evidence$data_kind) && evidence$data_kind == "synthetic_validation") stop("Synthetic evidence cannot be staged for publication.")
    if (!nrow(evidence$facts) || !all(evidence$facts$status == "AVAILABLE_CACHED")) stop("Core regional evidence is incomplete.")
    # Compare with actual cached daily data when a manifest is present. Never
    # present an older shared derived-grid date as current after a failed build.
    manifest <- file.path(root, "data/processed/prism/manifest.csv")
    if (file.exists(manifest)) {
      endpoint <- context$latest_common_prism_date(c("maxt", "mint", "pcpn"),
        processed_manifest = context$read_prism_manifest(manifest))
      if (as.character(endpoint) != date) stop("Synopsis derived grids lag the latest common daily PRISM date.")
    }
    draft <- context$build_conditions_synopsis_draft(evidence, root = root,
      output_dir = file.path(paths$directory, "draft"), track_preview = FALSE, show_review_candidates = FALSE,
      publication_snapshot = prior, comparison_origin = "successful_publication")
  }, error = function(e) {status <<- "WAITING"; note <<- conditionMessage(e)})
  site_base <- if(grepl("^s3://",destination)) sub("^s3://[^/]+/","https://cales.arizona.edu/",destination) else
    "https://cales.arizona.edu/climate/watch/"
  support_manifest <- data.frame()
  support_base <- ""
  if(status=="READY") {
    support_dir <- file.path(paths$directory,"draft/support")
    files <- sort(list.files(support_dir,pattern="\\.html$",full.names=TRUE))
    if(length(files)&&any(vapply(files,function(p)any(grepl('src="temperature-7day.png"',readLines(p,warn=FALSE),fixed=TRUE)),logical(1))))
      files <- c(files,file.path(support_dir,"temperature-7day.png"))
    if(length(files)) {
      key <- paste0(date,"-",substr(digest::digest(list(destination=destination,names=basename(files),md5=unname(tools::md5sum(files)))),1L,12L))
      target <- file.path(root,"site/synopsis-evidence",key)
      dir.create(target,recursive=TRUE,showWarnings=FALSE)
      if(!all(file.copy(files,target,overwrite=TRUE)))stop("Could not stage synopsis supporting evidence.")
      for(file in files[grepl("[.]html$",files)]) {
        html <- readLines(file,warn=FALSE,encoding="UTF-8")
        html <- gsub("https://cales.arizona.edu/climate/watch/",site_base,html,fixed=TRUE)
        writeLines(html,file.path(target,basename(file)),useBytes=TRUE)
      }
      support_manifest <- data.frame(path=file.path("synopsis-evidence",key,basename(files)),md5=unname(tools::md5sum(file.path(target,basename(files)))))
      support_base <- paste0("synopsis-evidence/",key,"/")
    }
  }
  for(i in seq_along(draft$blocks)) if(!is.null(draft$blocks[[i]]$support_link))
    draft$blocks[[i]]$links <- c(paste0(support_base,basename(draft$blocks[[i]]$support_link)),draft$blocks[[i]]$links)
  escape <- context$synopsis_escape_html
  settings <- context$synopsis_format_settings(if (is.null(evidence)) list(unusual_station_percentile = 90) else evidence$configuration)
  css <- if (settings$enabled) paste0('.synopsis-content .signal-', names(settings$colors), '{color:', unlist(settings$colors), ';}', collapse = '') else ''
  content <- c(paste0('<style>.synopsis-content{max-width:1050px;line-height:1.65}.synopsis-content h3{font-size:1.2rem;margin-top:1.5rem}.synopsis-content li{margin-bottom:14px}.synopsis-content small{font-size:.85em;color:#566b75}.synopsis-content details{margin:20px 0}.synopsis-waiting{padding:16px;background:#fff4df}.synopsis-date{color:#566b75}', css, '</style>'),
    paste0('<section class="synopsis-content" data-synopsis-status="', status, '" data-synopsis-date="', ifelse(is.na(date), "unavailable", date), '">'))
  if (status == "READY") {
    content <- c(content, paste0('<p class="synopsis-date"><strong>Data through ', escape(context$synopsis_date_text(date)), '</strong></p>'))
    for (section in c("Past 7 days", "Past 30 days", "Water year so far")) {
      blocks <- Filter(function(b) b$section == section, draft$blocks)
      content <- c(content, paste0('<h3>', section, '</h3><ul>'), vapply(blocks, function(b) paste0('<li>',
        context$synopsis_format_text(b$text, b$emphasis),
        if (length(b$links)) paste0('<br><small>', paste0('<a href="',site_base, escape(b$links), '">',
          ifelse(grepl('synopsis-evidence/',b$links,fixed=TRUE),'Evidence and matching dates',ifelse(grepl('station-conditions', b$links), 'Station Conditions', 'Related map')), '</a>', collapse = ' \u00b7 '), '</small>') else '', '</li>'), character(1)), '</ul>')
    }
    details <- jsonlite::read_json(file.path(paths$directory, "draft/draft-evidence.json"))
    limits <- unlist(details$limitations)
    limits <- sub("Public links may display a newer date than this local draft.", "Supporting products may use a newer observation date than this synopsis cutoff.", limits, fixed = TRUE)
    content <- c(content, '<p><a href="https://cales.arizona.edu/climate/watch/pages/current-snow.html">Current Snow: latest SWE and snowpack changes</a></p>',
      '<details><summary>Reading this synopsis</summary><ul>', paste0('<li>', escape(limits), '</li>'), '</ul></details>')
  } else content <- c(content, '<p class="synopsis-waiting"><strong>Synopsis temporarily unavailable.</strong> The current inputs did not pass the evidence checks. Use the Maps tab and individual products for the latest verified conditions.</p>')
  content <- c(content, '</section>')
  pages <- file.path(root, "site/pages"); dir.create(pages, recursive = TRUE, showWarnings = FALSE)
  writeLines(c('```{=html}', content, '```'), file.path(pages, "_synopsis-content.qmd"), useBytes = TRUE)
  writeLines(c('---', 'title: "Conditions synopsis"', 'toc: false', '---', '',
    '[Home dashboard](../index.qmd)', '', '{{< include _synopsis-content.qmd >}}'), file.path(pages, "synopsis.qmd"), useBytes = TRUE)
  payload <- list(status = status, date = date, destination = destination, note = note,
    support_manifest=support_manifest,
    fragment_md5 = unname(tools::md5sum(file.path(pages, "_synopsis-content.qmd"))))
  if (status == "READY") {
    snapshot <- context$synopsis_comparison_context(evidence, NULL)$state$latest
    payload$snapshot <- list(kind = "successful_publication", latest = snapshot)
  }
  saveRDS(payload, paths$pending)
  utils::write.csv(data.frame(status = status, date = date, note = note), file.path(paths$directory, "status.csv"), row.names = FALSE, na = "")
  message("Template synopsis: ", status, if (!is.na(date)) paste0(" (", date, ")") else "", "; no API requests.")
  invisible(payload)
}

validate_conditions_synopsis_publication <- function(output_dir, destination, root = ".") {
  paths <- synopsis_publication_paths(destination, root)
  if (!file.exists(paths$pending)) stop("Synopsis staging record is missing; S3 sync stopped.")
  payload <- readRDS(paths$pending)
  fragment <- file.path(root, "site/pages/_synopsis-content.qmd")
  if (!identical(payload$destination, destination) || !file.exists(fragment) ||
      !identical(payload$fragment_md5, unname(tools::md5sum(fragment)))) stop("Synopsis staging evidence changed; S3 sync stopped.")
  support <- payload$support_manifest
  if(is.data.frame(support)&&nrow(support)) {
    paths <- file.path(output_dir,support$path)
    if(!all(file.exists(paths))||!identical(unname(tools::md5sum(paths)),support$md5))
      stop("Rendered synopsis supporting evidence is missing or changed; S3 sync stopped.")
  }
  for (file in c("index.html", "pages/synopsis.html")) {
    path <- file.path(output_dir, file)
    if (!file.exists(path)) stop("Rendered synopsis/home page is missing; S3 sync stopped.")
    # Parse the file directly so libxml honors its UTF-8 declaration on Windows.
    doc <- xml2::read_html(path)
    nodes <- xml2::xml_find_all(doc, '//*[@data-synopsis-status]')
    if (length(nodes) != 1L || xml2::xml_attr(nodes, "data-synopsis-status") != payload$status ||
        xml2::xml_attr(nodes, "data-synopsis-date") != ifelse(is.na(payload$date), "unavailable", payload$date))
      stop("Rendered synopsis status/date does not match staged evidence; S3 sync stopped.")
    if (grepl("review candidates|AI-written|SYNTHETIC VALIDATION", xml2::xml_text(nodes), ignore.case = TRUE))
      stop("Development/AI synopsis content reached rendered output; S3 sync stopped.")
    if (payload$status == "READY" && !all(vapply(c("Past 7 days", "Past 30 days", "Water year so far"),
      function(s) grepl(s, xml2::xml_text(nodes), fixed = TRUE), logical(1)))) stop("Rendered synopsis sections are incomplete; S3 sync stopped.")
    if (file == "index.html") {
      tabs <- xml2::xml_find_all(doc, '//*[@role="tab"]')
      text <- trimws(xml2::xml_text(tabs))
      selected <- xml2::xml_attr(tabs, "aria-selected")
      if (!any(text == "Maps" & selected == "true", na.rm = TRUE) || !any(text == "Synopsis" & selected == "false", na.rm = TRUE))
        stop("Home Maps/Synopsis tabs are missing or Maps is not the default; S3 sync stopped.")
    }
  }
  invisible(payload)
}

commit_conditions_synopsis_publication <- function(destination, root = ".", dry_run = FALSE) {
  if (dry_run) return(invisible(FALSE))
  paths <- synopsis_publication_paths(destination, root)
  pending <- readRDS(paths$pending)
  # A waiting page must not become the baseline for future climate claims.
  if (!identical(pending$status, "READY")) return(invisible(FALSE))
  saveRDS(pending$snapshot, paths$success)
  invisible(TRUE)
}

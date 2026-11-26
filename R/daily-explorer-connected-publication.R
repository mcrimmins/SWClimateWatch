# Operational adapter: called after current weather/events and cache versions.
connected_publication_guard <- function(destination=Sys.getenv("SWC_S3_DESTINATION")) {
  states<-c("s3://cales-climate-reports/climate/watch/"="/home/crimmins/.local/state/swclimatewatch",
    "s3://cales-climate-reports/climate/watch-staging/"="/home/crimmins/.local/state/swclimatewatch-staging")
  if(length(destination)!=1L||is.na(destination)||!destination%in%names(states)||
     !identical(Sys.getenv("SWC_PRODUCTION_STATE_DIR"),unname(states[[destination]])))
    stop("Connected publication requires a matching dedicated destination/state pair.")
  if(any(tolower(Sys.getenv(c("SWC_DAILY_CONNECTED_STAGING","SWC_DAILY_WY2025_STAGING","SWC_DAILY_ARCHIVE_STAGING")))=="true"))
    stop("Clear archive trial flags before enabling operational connected publication.")
  invisible(TRUE)
}
connected_publication_page <- function(text,enabled=TRUE) {
  if(!enabled) {
    text<-gsub("../daily-explorer/connected/index.html","../daily-explorer/index.html",text,fixed=TRUE)
    return(sub("Explore daily conditions for the current water year and completed archive years.",
      "Explore daily PRISM precipitation and temperature for the current water year,\nwith the preceding September included for comparisons across October 1.",text,fixed=TRUE))
  }
  text<-gsub("../daily-explorer/index.html","../daily-explorer/connected/index.html",text,fixed=TRUE)
  text<-sub("Explore daily PRISM precipitation and temperature for the current water year,\nwith the preceding September included for comparisons across October 1.",
    "Explore daily conditions for the current water year and completed archive years.",text,fixed=TRUE)
  # The outer Quarto embed also settles its size instead of resizing for every
  # intermediate report/table update inside the connected viewer.
  old<-'const resize = () => { frame.style.height = `${Math.max(850, body.scrollHeight + 12)}px`; };'
  replacement<-'let pending, lastHeight = 2300;\n    const resize = () => { clearTimeout(pending); pending = setTimeout(() => { const height = Math.max(850, body.scrollHeight + 12); if (Math.abs(height - lastHeight) >= 4) { lastHeight = height; frame.style.height = `${height}px`; } }, 160); };'
  text<-sub(old,replacement,text,fixed=TRUE)
  if(!grepl("../daily-explorer/connected/index.html?embedded=1",text,fixed=TRUE))stop("Daily Explorer page hook needs review.")
  text
}
connected_publication_redirect <- function(text) {
  if(grepl("swc-connected-entry",text,fixed=TRUE))return(text)
  script<-'<script id="swc-connected-entry">if (window.top === window) { const target = new URL("connected/index.html", location.href); target.search = location.search; target.hash = location.hash; location.replace(target.href); }</script>'
  if(!grepl("</head>",text,fixed=TRUE))stop("Explorer entry hook needs review.")
  sub("</head>",paste0(script,"</head>"),text,fixed=TRUE)
}
stage_connected_publication <- function() {
  connected_publication_guard()
  source("scripts/load-daily-explorer-connected.R",local=FALSE)
  source("R/daily-explorer-connected-staging.R",local=TRUE)
  years<-c(2025L,2026L)
  for(year in years) {
    imported<-paste0("data/diagnostics/daily-explorer-wy",year,"-release")
    validate<-get(paste0("validate_wy",year,"_explorer_navigation"),mode="function")
    validate(imported)
    marker<-paste0("wy",year,"-release.json");release<-jsonlite::read_json(file.path(imported,marker))
    target<-file.path("site/daily-explorer/archive",paste0("wy",year))
    for(p in c(vapply(release$files,`[[`,character(1),"path"),marker))july_pilot_copy(file.path(imported,p),file.path(target,p))
  }
  build_connected_static("site/daily-explorer",file.path("site/daily-explorer/archive",paste0("wy",years)),validate_archive=FALSE,publication=TRUE)
  page<-"site/pages/daily-explorer.qmd"
  text<-paste(readLines(page,warn=FALSE),collapse="\n")
  writeLines(connected_publication_page(text),page,useBytes=TRUE)
}
validate_connected_publication <- function(output_dir="site/_site") {
  connected_publication_guard()
  source("scripts/load-daily-explorer-connected.R",local=FALSE)
  source("R/daily-explorer-connected-staging.R",local=TRUE)
  roots<-c("site/daily-explorer",file.path(output_dir,"daily-explorer"))
  for(year in c(2025L,2026L)) {
    marker<-paste0("wy",year,"-release.json")
    imported<-file.path(paste0("data/diagnostics/daily-explorer-wy",year,"-release"),marker)
    expected<-unname(tools::md5sum(imported))
    if(is.na(expected))stop("Missing imported archive release: ",year)
    for(root in roots) {
      target<-file.path(root,"archive",paste0("wy",year))
      if(!identical(expected,unname(tools::md5sum(file.path(target,marker)))))stop("Imported/source/rendered archive releases differ: ",year)
      get(paste0("validate_wy",year,"_explorer_navigation"),mode="function")(target)
    }
  }
  for(root in roots) {
    validate_connected_static(root)
    release<-jsonlite::read_json(file.path(root,"connected/connected-release.json"))
    if(!isTRUE(release$operational))stop("Connected operational release is missing.")
    if(!identical(as.integer(unlist(release$archive_years)),c(2025L,2026L)))stop("Both archive years are required.")
  }
  seals<-unname(tools::md5sum(file.path(roots,"connected/connected-release.json")))
  if(anyNA(seals)||length(unique(seals))!=1L)stop("Connected source/rendered release mismatch.")
  for(root in roots)if(!grepl("swc-connected-entry",paste(readLines(file.path(root,"index.html")),collapse="\n"),fixed=TRUE))stop("Full-screen Explorer entry is not connected.")
  page<-file.path(output_dir,"pages/daily-explorer.html")
  if(!file.exists(page)||!grepl("../daily-explorer/connected/index.html?embedded=1",paste(readLines(page,warn=FALSE),collapse="\n"),fixed=TRUE))
    stop("Standard Daily Explorer page is not connected.")
  message("PASS: standard Daily Explorer, both archive years and current connected publication.")
}

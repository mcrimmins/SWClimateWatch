# Refresh only the Home Maps footer; retain cached cards, dates and synopsis.
# No downloads, map calculations, live ENSO requests, rendering or publication.
source("R/config.R")
source("R/acis-prism.R")
source("R/process-prism.R")
source("R/map-product-site.R")
home_layout_path <- "site/index.qmd"
home_layout_text <- readLines(home_layout_path,warn=FALSE,encoding="UTF-8")
home_layout_start <- which(home_layout_text=="<!-- BEGIN HOME MAP FOOTER -->")
home_layout_end <- which(home_layout_text=="<!-- END HOME MAP FOOTER -->")
if(!length(home_layout_start)) {
  home_layout_start <- which(home_layout_text=="::: {.dashboard-note}")
  home_layout_end <- which(home_layout_text=="## Synopsis")-1L
}
if(length(home_layout_start)!=1L||length(home_layout_end)!=1L||home_layout_start>=home_layout_end)
  stop("Could not identify one Home Maps footer. Source page was not changed.")
home_layout_dashboard <- read_map_dashboard_config()
home_layout_years <- as.integer(sub("^wy([0-9]{4})\\.qmd$","\\1",list.files("site/pages/archive",pattern="^wy[0-9]{4}\\.qmd$")))
home_layout_footer <- map_dashboard_footer_text(home_layout_dashboard,
  snow=list(available=any(grepl("SNODAS \u00b7",home_layout_text,fixed=TRUE))),archive_years=home_layout_years,
  show_headlines=any(grepl("::: {.dashboard-headlines}",home_layout_text,fixed=TRUE)))
home_layout_tail <- home_layout_text[seq.int(home_layout_end+1L,length(home_layout_text))]
while(length(home_layout_tail)&&!nzchar(trimws(home_layout_tail[1]))) home_layout_tail <- home_layout_tail[-1L]
current_map_group_write(c(home_layout_text[seq_len(home_layout_start-1L)],home_layout_footer,"",
  home_layout_tail),home_layout_path)
message("Home Maps footer refreshed. Existing map cards, dates and synopsis retained.")

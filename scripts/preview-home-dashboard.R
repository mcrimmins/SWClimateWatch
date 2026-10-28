# Local layout preview using existing PNGs only. No downloads, maps or S3 sync.
source("R/config.R")
source("R/acis-prism.R")
source("R/process-prism.R")
source("R/build-current-prism-maps.R")
source("R/map-product-site.R")
directory<-file.path("data","diagnostics","home-dashboard-preview")
dir.create(directory,recursive=TRUE,showWarnings=FALSE)
dashboard<-read_map_dashboard_config()
dates<-map_product_expected_data_dates()
snow<-map_dashboard_snow_selection()
years<-as.integer(sub("^wy([0-9]{4})\\.qmd$","\\1",
  list.files(file.path("site","pages","archive"),pattern="^wy[0-9]{4}\\.qmd$")))
summaries<-map_dashboard_summaries(dates,dashboard=dashboard)
headlines<-map_dashboard_headlines(dates,dashboard=dashboard)
page<-map_dashboard_page_text(dashboard,dates,snow=snow,archive_years=years,summaries=summaries,headlines=headlines)
writeLines(page,file.path("site","index.qmd"),useBytes=TRUE)
copy<-function(from,to) {
  dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE)
  if(!file.copy(from,to,overwrite=TRUE)) stop("Preview input unavailable: ",from)
}
preview_page<-function(lines,name) {
  images<-unique(regmatches(lines,gregexpr("(?:maps/generated|assets/branding)/[^)]+\\.png",lines,perl=TRUE)))
  for(image in unique(unlist(images))) copy(file.path("site",image),file.path(directory,image))
  # Preview links lead to existing public detail pages; production source keeps
  # relative Quarto links, resolved by the normal site renderer.
  lines<-gsub("(\\]\\()(pages/[^)]+)\\.qmd(\\))",
    "\\1https://cales.arizona.edu/climate/watch/\\2.html\\3",lines)
  writeLines(lines,file.path(directory,name),useBytes=TRUE)
}
example<-file.path("data","diagnostics","snodas-daily-comparison-pilot","2023-03-01-percent-median.png")
has_example<-file.exists(example) && file.info(example)$size>10000
page<-append(page,c("::: {.dashboard-note}",
  "**Local dashboard preview — cached laptop maps.** No site publication or new data downloads.",
  if(has_example) "[Historical snow-card layout example](snow-example.qmd)" else character(),":::",""),after=which(page=="---")[2]+1L)
preview_page(page,"index.qmd")
if(has_example) {
  image<-"maps/generated/snodas/current/swe-percent-median.png"
  demo<-map_dashboard_page_text(dashboard,dates,
    snow=list(available=TRUE,date="2023-03-01",image=image,page="pages/current-snow.qmd"),archive_years=years,summaries=summaries,headlines=headlines)
  # Copy this historical sample only into the separate preview; never site/.
  dir.create(dirname(file.path(directory,image)),recursive=TRUE,showWarnings=FALSE)
  copy(example,file.path(directory,image))
  demo<-gsub("(\\]\\()(pages/[^)]+)\\.qmd(\\))",
    "\\1https://cales.arizona.edu/climate/watch/\\2.html\\3",demo)
  demo<-append(demo,c("::: {.dashboard-note}",
    "**Historical snow-card layout example.** March 1, 2023 snow is shown alongside cached laptop PRISM maps solely to review layout; these are not contemporaneous conditions.",
    "[Return to current cached preview](index.qmd)",":::",""),after=which(demo=="---")[2]+1L)
  writeLines(demo,file.path(directory,"snow-example.qmd"),useBytes=TRUE)
}
copy(file.path("site","styles.css"),file.path(directory,"styles.css"))
copy(file.path("site","filters","dashboard-status.lua"),file.path(directory,"filters","dashboard-status.lua"))
for(image in c("southwest-climate-watch-mark-transparent.png","ua-csap-climas-logos-horizontal.png"))
  copy(file.path("site","assets","branding",image),file.path(directory,"assets","branding",image))
sidebar<-yaml::read_yaml(file.path("site","_quarto.yml"))$website$sidebar
preview_links<-function(node) {
  if(!is.list(node)) return(node)
  if(is.character(node$href) && node$href!="index.qmd" && grepl("\\.qmd$",node$href))
    node$href<-paste0("https://cales.arizona.edu/climate/watch/",sub("\\.qmd$",".html",node$href))
  lapply(node,preview_links)
}
configuration<-yaml::as.yaml(list(project=list(type="website"),
  website=list(title="Southwest Climate Watch",sidebar=preview_links(sidebar)),
  format=list(html=list(theme="flatly",css="styles.css"))))
# R's YAML writer uses YAML 1.1 yes/no; Quarto expects true/false.
configuration<-gsub("(?m)^([ ]*[^:\n]+:) yes$","\\1 true",configuration,perl=TRUE)
configuration<-gsub("(?m)^([ ]*[^:\n]+:) no$","\\1 false",configuration,perl=TRUE)
writeLines(configuration,file.path(directory,"_quarto.yml"),useBytes=TRUE)
message("Dashboard preview source ready: ",directory)
message("Seasonal selection: ",if(isTRUE(snow$available)) "SWE percent of median" else snow$reason)

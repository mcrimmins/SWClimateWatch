# Fast synthetic display review. Never rebuilds operational grids or publishes.
source('scripts/load-prism-review-fixes.R')
directory <- 'data/diagnostics/prism-code-review'
dir.create(directory,recursive=TRUE,showWarnings=FALSE)
template <- terra::rast(nrows=12,ncols=12,xmin=-115.6,xmax=-102.45,ymin=30.75,ymax=37.6,crs='EPSG:4326')
value <- function(x) terra::setValues(template,rep(x,length.out=terra::ncell(template)))
observed <- value(c(60,100,0,NA)); normal <- value(93)
first <- prism_first_freeze_departure_raster(observed,normal,'2026-12-01')
bound <- prism_first_freeze_late_bound(observed,normal,'2026-12-01')
first_plot <- build_prism_first_freeze_map(first,'departure',date=as.Date('2026-12-01'),status_raster=bound)
observed <- value(c(240,270,250,NA)); normal <- value(258)
last <- prism_last_freeze_departure_raster(observed,normal,'2027-04-30')
pending <- terra::ifel(!is.na(observed) & is.na(last),1,NA)
last_plot <- build_prism_last_freeze_map(last,'departure',date=as.Date('2027-04-30'),status_raster=pending)
for(name in c('first','last')) {
  plot <- get(paste0(name,'_plot')) + ggplot2::labs(title=paste('Synthetic review:',name,'freeze status'))
  save_southwest_map(plot,file.path(directory,paste0(name,'-freeze-status.png')),
    logo_path=southwest_brand_logo_path(),footer_text='SYNTHETIC REGRESSION EXAMPLE — not observed weather; not published')
}
writeLines(c('<!doctype html><html><head><meta charset="utf-8"><title>PRISM comparison fixes: synthetic review</title><style>body{font:16px system-ui;max-width:1300px;margin:auto;padding:20px}img{width:100%}</style></head><body>',
  '<h1>PRISM comparison fixes: synthetic display review</h1><p>These block patterns test status colors and legends; they are not observations or climatology outputs.</p>',
  '<h2>First freeze</h2><p>Colored departures are observed events; purple means complete observations with no event yet after the median date. Missing inputs remain blank.</p><img src="first-freeze-status.png" alt="Synthetic first-freeze comparison">',
  '<h2>Last freeze</h2><p>Gray means the season remains in progress under the median-date and 14-freeze-free-day gates. Current numeric comparisons remain provisional until July 31.</p><img src="last-freeze-status.png" alt="Synthetic last-freeze comparison">',
  '</body></html>'),file.path(directory,'index.html'),useBytes=TRUE)
if(interactive()) utils::browseURL(normalizePath(file.path(directory,'index.html'),winslash='/'))
message('Synthetic review ready: ',directory,'/index.html. No requests, operational map changes or publication.')

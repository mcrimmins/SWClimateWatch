# Independently extract original daily observations at eight locations.
source('scripts/load-regional-daily-reference.R')
root <- 'data/diagnostics/regional-daily-reference-pilot'
marker <- readRDS(file.path(root,'complete.rds'))
stopifnot(all(file.exists(marker$files)),identical(unname(tools::md5sum(marker$files)),marker$md5))
plan <- read.csv(file.path(root,'input-plan.csv'),stringsAsFactors=FALSE)
stopifnot(all(plan$complete),identical(unname(tools::md5sum(plan$path)),plan$md5))
samples <- read.csv('data/diagnostics/regional-climate-reference-pilot/samples.csv',stringsAsFactors=FALSE)
points <- as.matrix(samples[c('longitude','latitude')]); records <- list()
for (i in seq_len(nrow(plan))) {
  raster <- read_prism_daily_raster(plan$path[i],plan$variable[i],validate_values=FALSE)
  values <- as.matrix(terra::extract(raster,points))
  if (ncol(values)==terra::nlyr(raster)+1L) values <- values[,-1,drop=FALSE]
  records[[i]] <- list(variable=plan$variable[i], dates=as.Date(terra::time(raster)),values=values)
  if (i%%90L==0L) message('Independent daily check: ',i,'/',nrow(plan),' files sampled.')
}
series <- lapply(c('pcpn','mint','maxt'),function(variable) {
  rows <- records[vapply(records,function(x) x$variable==variable,logical(1))]
  list(dates=as.Date(unlist(lapply(rows,`[[`,'dates')),origin='1970-01-01'),values=do.call(cbind,lapply(rows,`[[`,'values')))
}); names(series) <- c('pcpn','mint','maxt')
stopifnot(identical(series$pcpn$dates,series$mint$dates),identical(series$pcpn$dates,series$maxt$dates))
dates <- series$pcpn$dates; checks <- list()
periods <- c(list(annual=1:12),lapply(regional_reference_seasons(),`[[`,'months'))
for (period in names(periods)) {
  expected <- matrix(NA_real_,nrow(points),5,dimnames=list(NULL,names(regional_daily_specs())))
  for (cell in seq_len(nrow(points))) {
    yearly <- lapply(1991:2020,function(year) {
      selected <- format(dates,'%Y')==as.character(year) & as.integer(format(dates,'%m')) %in% periods[[period]]
      p <- series$pcpn$values[cell,selected]; lo <- series$mint$values[cell,selected]; hi <- series$maxt$values[cell,selected]
      bad <- is.finite(lo) & is.finite(hi) & lo>hi; lo[bad] <- hi[bad] <- NA_real_
      valid_p <- all(is.finite(p) & p>=0 & p<=swc_prism$plausible_ranges$pcpn[2])
      valid_lo <- all(is.finite(lo) & lo>=swc_prism$plausible_ranges$mint[1] & lo<=swc_prism$plausible_ranges$mint[2])
      valid_hi <- all(is.finite(hi) & hi>=swc_prism$plausible_ranges$maxt[1] & hi<=swc_prism$plausible_ranges$maxt[2])
      c(wet=if(valid_p) sum(p>=.04-1e-7) else NA_real_,amount=if(valid_p) sum(p[p>=.04-1e-7]) else NA_real_,
        heavy=if(valid_p) sum(p>=1-1e-7) else NA_real_,freeze=if(valid_lo) sum(lo<=32+1e-6) else NA_real_,hot=if(valid_hi) sum(hi>=90-1e-6) else NA_real_)
    })
    x <- do.call(rbind,yearly)
    expected[cell,] <- c(mean(x[,'wet']),if(all(is.finite(x[,'wet'])) && sum(x[,'wet'])>0) sum(x[,'amount'])/sum(x[,'wet']) else NA_real_,mean(x[,'heavy']),mean(x[,'freeze']),mean(x[,'hot']))
  }
  for (metric in colnames(expected)) {
    value <- terra::extract(terra::rast(file.path(root,period,paste0(metric,'.tif'))),points)
    actual <- as.numeric(value[[ncol(value)]])
    pass <- (is.na(actual)&is.na(expected[,metric])) | (is.finite(actual)&is.finite(expected[,metric])&abs(actual-expected[,metric])<1e-4)
    checks[[length(checks)+1L]] <- data.frame(location=samples$location,period=period,metric=metric,expected=expected[,metric],actual=actual,status=ifelse(pass,'PASS','FAIL'))
  }
}
regional_daily_check <- do.call(rbind,checks)
write.csv(regional_daily_check,file.path(root,'independent-check.csv'),row.names=FALSE)
print(with(regional_daily_check,table(period,status)))
stopifnot(all(regional_daily_check$status=='PASS'))
message('PASS: 200 independent daily-reference comparisons; output/input checksums verified. No downloads or publication.')

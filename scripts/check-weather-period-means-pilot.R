# Independent point checks against selected raw GRIB cells (no downloads).
source("scripts/load-weather-circulation-pilot.R")
source("R/weather-moisture-pilot.R")
source("R/weather-seven-day-pilot.R")
source("R/weather-period-means-pilot.R")
root<-"data/diagnostics/weather-period-means-pilot"
reports<-list()
for(days in c(1L,7L,30L)) {
  result<-readRDS(file.path(root,paste0(days,"day"),"mean-native-grid.rds"))
  cells<-result$cells
  reference<-weather_core_grid(result$inputs$path[result$inputs$field=="height500"][1])
  targets<-data.frame(x=c(170,220,249),y=c(45,30,35))
  selected<-vapply(seq_len(nrow(targets)),function(i)which.min((cells$x-targets$x[i])^2+(cells$y-targets$y[i])^2),integer(1))
  raw<-lapply(split(result$inputs,result$inputs$field),function(inputs) {
    daily<-lapply(inputs$path,function(path) {
      grid<-weather_moisture_grid(path,reference);r<-terra::rast(path)
      xx<-terra::xFromCol(r,seq_len(terra::ncol(r)));xx<-ifelse(xx<120,xx+360,xx)
      row<-vapply(cells$y[selected],function(y)which.min(abs(grid$latitude-y)),integer(1))
      col<-vapply(cells$x[selected],function(x)which.min(abs(xx-x)),integer(1))
      terra::values(r,mat=FALSE)[terra::cellFromRowCol(r,row,col)]
    })
    rowMeans(do.call(cbind,daily))
  })
  expected<-cbind(height_dm=raw$height500/10,pwat_inches=raw$pwat/25.4,
    speed_knots=sqrt(raw$u250^2+raw$v250^2)*1.943844)
  actual<-as.matrix(cells[selected,colnames(expected)])
  stopifnot(all(abs(actual-expected)<1e-8))
  reports[[length(reports)+1L]]<-data.frame(days,x=cells$x[selected],y=cells$y[selected],maximum_error=apply(abs(actual-expected),1,max))
}
write.csv(do.call(rbind,reports),file.path(root,"raw-point-checks.csv"),row.names=FALSE)
message("PASS: height, PWAT and vector-mean jet speed match raw GRIB cells at three locations for every period.")

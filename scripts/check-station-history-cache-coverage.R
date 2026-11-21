# Refuse to replace the full-record seed with a shorter local station cache.
source("scripts/load-station-custom-dates-pilot.R")
catalog <- jsonlite::read_json(file.path(station_custom_pilot_root(),"catalog.json"),simplifyVector=TRUE)$stations
coverage <- do.call(rbind,lapply(seq_len(nrow(catalog)),function(i) {
  station <- catalog[i,]
  cache <- acis_station_read_daily_cache(acis_station_daily_cache_path(station$uid),station$uid)
  first <- if(is.null(cache)) as.Date(NA) else min(cache$daily$date)
  last <- if(is.null(cache)) as.Date(NA) else cache$as_of
  data.frame(uid=station$uid,name=station$name,seed_first=station$first,seed_last=station$last,
    cache_first=as.character(first),cache_last=as.character(last),
    passed=!is.na(first)&&!is.na(last)&&first<=as.Date(station$first)&&last>=as.Date(station$last))
}))
write.csv(coverage,file.path(station_custom_pilot_root(),"source-coverage.csv"),row.names=FALSE)
if(any(!coverage$passed)) {
  print(coverage[!coverage$passed,],row.names=FALSE)
  stop("Station source caches are shorter/older than the transferred full-record seed. Stop here and arrange the missing full station caches; no history rebuild or upload was attempted.")
}
message("PASS: ",nrow(coverage)," local station caches cover at least the historical seed's dates.")

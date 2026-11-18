source(file.path(project_root,"R","weather-publication-audit.R"))
source(file.path(project_root,"R","daily-publish.R"))

weather_publication_fixture<-function(root) {
  source<-file.path(root,"source"); rendered<-file.path(root,"rendered","daily-explorer")
  archive<-file.path(root,"archive")
  dates<-as.character(seq(as.Date("2026-09-01"),as.Date("2026-10-05"),by="day"))
  for(path in c(source,rendered)) dir.create(file.path(path,"circulation","maps"),recursive=TRUE)
  payload<-list(circulation_enabled=TRUE,latest_cached_date=tail(dates,1),
    days=lapply(dates,function(date) list(date=date)))
  records<-lapply(dates,function(date) {
    fields<-c("height500","jet250","moisture")
    images<-setNames(paste0("circulation/maps/",date,"-",fields,".png"),fields)
    for(image in images) for(path in c(source,rendered)) writeLines(date,file.path(path,image))
    list(date=date,status="available",images=as.list(images))
  })
  manifest<-list(schema_version=1L,days=records)
  for(path in c(source,rendered)) {
    jsonlite::write_json(payload,file.path(path,"daily-data.json"),auto_unbox=TRUE)
    jsonlite::write_json(manifest,file.path(path,"circulation-manifest.json"),auto_unbox=TRUE)
  }
  notes<-c("1 hourly pressure sample(s) recovered from GRIB despite incomplete index.",
    "Moisture wind overlay omitted: incomplete hourly terrain-screening inputs.",
    "H/L omitted: incomplete daily surface-pressure screening.")
  for(i in seq_along(notes)) {
    path<-file.path(archive,"daily",dates[i]); dir.create(path,recursive=TRUE)
    hash<-unname(tools::md5sum(file.path(source,paste0("circulation/maps/",dates[i],"-moisture.png"))))
    saveRDS(list(note=notes[i],md5=hash),file.path(path,"moisture-map-cache.rds"))
  }
  list(source=source,rendered=rendered,archive=archive,manifest=manifest,payload=payload)
}

testthat::test_that("weather report distinguishes coverage and known/unknown overlays without downloads", {
  root<-tempfile(); dir.create(root); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  f<-weather_publication_fixture(root)
  report<-audit_weather_publication(f$source,f$rendered,f$archive,
    report_dir=file.path(root,"report"),today=as.Date("2026-10-06"))
  s<-report$summary
  testthat::expect_equal(s$status,"PASS")
  testthat::expect_equal(s$recent_expected,30)
  testthat::expect_equal(s$recent_available,30)
  testthat::expect_equal(s$available_dates,35)
  testthat::expect_equal(s$retained_maps,105)
  testthat::expect_equal(s$recovered_dates,1)
  testthat::expect_equal(s$wind_withheld_dates,1)
  testthat::expect_equal(s$centers_withheld_dates,1)
  testthat::expect_equal(s$unknown_overlay_dates,32)
  testthat::expect_true(file.exists(file.path(root,"report","summary.csv")))
  testthat::expect_equal(nrow(utils::read.csv(file.path(root,"report","dates.csv"))),35)
  f$manifest$days<-f$manifest$days[-10]
  for(path in c(f$source,f$rendered)) jsonlite::write_json(f$manifest,
    file.path(path,"circulation-manifest.json"),auto_unbox=TRUE)
  gap<-audit_weather_publication(f$source,f$rendered,f$archive,report_dir=NULL,today=as.Date("2026-10-06"))
  testthat::expect_equal(gap$summary$status,"WARN")
  testthat::expect_equal(gap$summary$missing_dates,1)
  testthat::expect_equal(gap$summary$recent_available,29)
  testthat::expect_equal(gap$dates$date[!gap$dates$weather_available],"2026-09-10")
})

testthat::test_that("rendered mismatches and erased flags are reported and quarantine only weather", {
  withr::local_envvar(c(SWC_WEATHER_MAPS="false"))
  root<-tempfile(); dir.create(root); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  f<-weather_publication_fixture(root)
  image<-file.path(f$rendered,"circulation/maps/2026-10-05-moisture.png")
  writeLines("bad",image)
  bad<-audit_weather_publication(f$source,f$rendered,f$archive,report_dir=NULL,today=as.Date("2026-10-06"))
  testthat::expect_equal(bad$summary$status,"FAIL")
  testthat::expect_match(bad$summary$note,"missing or different")
  source_image<-file.path(f$source,"circulation/maps/2026-10-05-moisture.png")
  saved<-readLines(source_image)
  writeLines(character(),source_image)
  incomplete<-audit_weather_publication(f$source,f$rendered,f$archive,report_dir=NULL,today=as.Date("2026-10-06"))
  testthat::expect_equal(incomplete$summary$available_dates,34)
  testthat::expect_equal(incomplete$summary$status,"FAIL")
  writeLines(saved,source_image)
  writeLines("2026-10-05",image)
  f$payload$circulation_enabled<-NULL
  for(path in c(f$source,f$rendered)) jsonlite::write_json(f$payload,
    file.path(path,"daily-data.json"),auto_unbox=TRUE)
  check<-audit_weather_publication(f$source,f$rendered,f$archive,report_dir=NULL,today=as.Date("2026-10-06"))
  testthat::expect_equal(check$summary$status,"FAIL")
  testthat::expect_match(check$summary$note,"Staged weather panel flag")
  testthat::expect_match(check$summary$note,"Rendered weather panel flag")
  testthat::expect_warning(result<-swc_daily_publish_validate_weather(dirname(f$rendered),f$source,
    expected_enabled=TRUE,report_dir=file.path(root,"report")),"panel disabled")
  testthat::expect_false(result)
  testthat::expect_equal(attr(result,"weather_report")$status,"FAIL")
  testthat::expect_true(attr(result,"weather_report")$quarantined)
  testthat::expect_false(jsonlite::read_json(file.path(f$rendered,"daily-data.json"))$circulation_enabled)
  testthat::expect_null(jsonlite::read_json(file.path(f$source,"daily-data.json"))$circulation_enabled)
  testthat::expect_equal(length(jsonlite::read_json(file.path(f$rendered,"daily-data.json"))$days),35)
})

testthat::test_that("disabled weather remains a deliberate no-op and summary includes coverage", {
  withr::local_envvar(c(SWC_WEATHER_MAPS="false"))
  root<-tempfile(); dir.create(root); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  f<-weather_publication_fixture(root)
  f$payload$circulation_enabled<-FALSE
  for(path in c(f$source,f$rendered)) jsonlite::write_json(f$payload,
    file.path(path,"daily-data.json"),auto_unbox=TRUE)
  testthat::expect_true(swc_daily_publish_validate_weather(dirname(f$rendered),f$source,expected_enabled=FALSE))
  s<-audit_weather_publication(f$source,f$rendered,f$archive,report_dir=NULL,
    today=as.Date("2026-10-06"),require_enabled=FALSE)$summary
  testthat::expect_equal(s$status,"DISABLED")
  lines<-swc_daily_publish_summary_lines(list(status="PUBLISHED",elapsed_seconds=60),
    weather=list(status="READY",days=35,built=1,reused=0,failed=0,pending=0,
      latest="2026-10-05",coverage=s))
  testthat::expect_true(any(grepl("Weather coverage: 30/30 recent dates, 35/35 Explorer dates",lines,fixed=TRUE)))
  result<-run_swc_daily_publish(today=as.Date("2026-10-06"),dry_run=TRUE,force_publish=TRUE,
    marker_path=file.path(root,"marker"),log_path=NULL,
    prism_update=function() list(summary=data.frame(data_changed=FALSE)),
    explorer_update=function() list(status="STAGED",days=35,maps=245,built=0,reused=35),
    weather_update=function(today) list(status="READY",days=35,built=0,reused=0,failed=0,pending=0,latest="2026-10-05"),
    snow_update=function(today) list(maps=list(status="OUT_OF_SEASON")),
    station_update=function(today) list(status="UPDATED"),site_fingerprint=function() "fixture",
    publish=function(dry_run) list(weather_validation=TRUE,weather_report=s),notify=function(...) NULL)
  testthat::expect_equal(result$weather$coverage,s)
  testthat::expect_true(any(grepl("Weather coverage: 30/30 recent dates",result$summary_lines,fixed=TRUE)))
})

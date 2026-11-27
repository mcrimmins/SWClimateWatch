recovery_root <- normalizePath(testthat::test_path("../.."),winslash="/",mustWork=TRUE)
source(file.path(recovery_root,"R/map-cleanup-recovery.R"))

recovery_fixture <- function() {
  root<-normalizePath(tempdir(),winslash="/",mustWork=TRUE)
  root<-tempfile("recovery-fixture-",tmpdir=root);dir.create(root)
  paths<-c(paste0("site/maps/generated/prism/temperature/maxt-value-2020-01-0",1:2,".png"),
    "site/maps/generated/prism/precipitation/pcpn-very-wet-contribution-percentile-rank-090day-2020-01-01.png")
  for(p in paths) {
    f<-file.path(root,p);dir.create(dirname(f),recursive=TRUE,showWarnings=FALSE)
    writeBin(as.raw(1:100),f)
  }
  info<-file.info(file.path(root,paths))
  rows<-data.frame(path=paths,bytes=info$size,modified=as.character(info$mtime),status="REVIEW_CANDIDATE",
    reference_count=0L,outside_project=FALSE)
  audit<-file.path(root,"data/diagnostics/map-cleanup-audit");dir.create(audit,recursive=TRUE)
  write.csv(rows,file.path(audit,"inventory.csv"),row.names=FALSE)
  write.csv(rows,file.path(audit,"proposed-cleanup.csv"),row.names=FALSE)
  write.csv(data.frame(path=character(),reason=character()),file.path(audit,"scan-issues.csv"),row.names=FALSE)
  list(root=root,paths=paths,audit=audit)
}

testthat::test_that("bundles round-trip with exact hashes, retain originals and reject corruption",{
  f<-recovery_fixture();withr::defer(unlink(f$root,recursive=TRUE))
  originals<-file.path(f$root,f$paths);before<-map_recovery_sha(originals)
  bundle<-prepare_map_cleanup_recovery(f$root)
  testthat::expect_identical(before,map_recovery_sha(originals))
  testthat::expect_false(bundle$summary$deletion_enabled)
  testthat::expect_equal(bundle$summary$files,3)
  testthat::expect_true(file.exists(file.path(bundle$directory,"archive-notes.txt")))
  testthat::expect_true(file.exists(file.path(bundle$directory,"READY.txt")))
  testthat::expect_equal(verify_map_cleanup_bundle(bundle$directory,f$root)$status,"PASS")
  archive<-file.path(bundle$directory,"recovery.tar.gz")
  con<-file(archive,"ab");writeBin(as.raw(0),con);close(con)
  testthat::expect_error(verify_map_cleanup_bundle(bundle$directory),"checksum mismatch")
  testthat::expect_identical(before,map_recovery_sha(originals))
})

testthat::test_that("missing, changed, unsafe and referenced files cannot be prepared",{
  for(mode in c("missing","changed","unsafe","referenced","issues")) {
    f<-recovery_fixture();withr::defer(unlink(f$root,recursive=TRUE))
    if(mode=="missing")unlink(file.path(f$root,f$paths[1]))
    if(mode=="changed")writeBin(as.raw(1:101),file.path(f$root,f$paths[1]))
    if(mode%in%c("unsafe","referenced")) {
      for(name in c("inventory.csv","proposed-cleanup.csv")) {
        p<-file.path(f$audit,name);x<-read.csv(p)
        if(mode=="unsafe")x$path[1]<-"site/maps/generated/prism/temperature/../../outside.png"
        else x$reference_count[1]<-1L
        write.csv(x,p,row.names=FALSE)
      }
    }
    if(mode=="issues")write.csv(data.frame(path="bad",reason="unreadable"),file.path(f$audit,"scan-issues.csv"),row.names=FALSE)
    testthat::expect_error(prepare_map_cleanup_recovery(f$root))
    testthat::expect_false(dir.exists(file.path(f$root,"data/diagnostics/map-cleanup-recovery")))
  }
})

testthat::test_that("post-preparation source changes and incomplete preparations are detected",{
  f<-recovery_fixture();withr::defer(unlink(f$root,recursive=TRUE))
  b<-prepare_map_cleanup_recovery(f$root)
  # Same length and restored mtime: SHA-256 still detects changed contents.
  p<-file.path(f$root,f$paths[1]);stamp<-file.info(p)$mtime
  writeBin(as.raw(2:101),p);Sys.setFileTime(p,stamp)
  testthat::expect_error(verify_map_cleanup_bundle(b$directory,f$root),"Original maps changed")
  testthat::expect_equal(verify_map_cleanup_bundle(b$directory)$status,"PASS")
  unlink(file.path(b$directory,"READY.txt"))
  testthat::expect_error(verify_map_cleanup_bundle(b$directory),"incomplete")
})

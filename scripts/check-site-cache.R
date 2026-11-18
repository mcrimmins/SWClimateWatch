# Read-only local publication check; no downloads or S3 changes.
source("R/site-cache.R")
for(root in c("site","site/_site"))for(app in c("daily-explorer","stations")) {
  directory<-file.path(root,app)
  assets<-swc_cache_validate_app(directory)
  if(!length(assets))stop("Application still has unversioned assets: ",directory)
  message("Cache asset check: PASS; ",length(assets)-1L," versioned assets; ",directory)
}

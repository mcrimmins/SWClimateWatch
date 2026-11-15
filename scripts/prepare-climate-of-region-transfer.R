# Laptop only: create the portable publication cache and a relative-path tarball.
source('scripts/load-regional-daily-reference.R')
source('R/regional-climate-site.R')
source('R/regional-precipitation-share.R')
source('R/regional-climate-release.R')
release_dir <- prepare_regional_climate_release()
output_dir <- 'data/diagnostics/regional-climate-transfer'
dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
regional_climate_archive <- file.path(output_dir,'swc-regional-climate-seed.tar.gz')
release <- verify_regional_climate_release(release_dir)$release
files <- file.path(release_dir,c(release$files$file,'release.json'))
utils::tar(regional_climate_archive,files=files,compression='gzip',tar='internal')
members <- utils::untar(regional_climate_archive,list=TRUE,tar='internal')
if(!setequal(members,files) || anyDuplicated(members)) stop('Transfer archive contents do not match the verified release.')
hash <- digest::digest(file=regional_climate_archive,algo='sha256')
writeBin(charToRaw(paste0(hash,'  ',basename(regional_climate_archive),'\n')),paste0(regional_climate_archive,'.sha256'))
cat('Archive:',regional_climate_archive,'\nSHA256:',hash,'\nSize:',round(file.info(regional_climate_archive)$size/1024^2,1),'MiB\n')
message('Transfer this tar.gz and its .sha256 file. Contains 39 PNGs and verification records; no raw grids, TIFFs or yearly computation caches.')

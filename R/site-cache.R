# Browser/CDN-safe application assets. Hash filenames, not query strings.
swc_cache_version_app <- function(directory) {
  index<-file.path(directory,"index.html")
  if(!file.exists(index))return(invisible(character()))
  html<-paste(readLines(index,warn=FALSE,encoding="UTF-8"),collapse="\n")
  matches<-unique(regmatches(html,gregexpr('(src|href)="[A-Za-z0-9_.-]+\\.(js|css)(\\?[^"<>]*)?"',html,perl=TRUE))[[1]])
  rows<-list()
  for(match in matches) {
    asset<-sub('^(src|href)="([^"?]+).*','\\2',match,perl=TRUE)
    canonical<-sub('\\.swc-[a-f0-9]{16}(\\.(js|css))$','\\1',asset,perl=TRUE)
    path<-file.path(directory,canonical)
    if(!file.exists(path)||file.info(path)$size<=0)stop("Missing cache-version source asset: ",path)
    hash<-unname(tools::md5sum(path));versioned<-sub('(\\.(js|css))$',paste0(".swc-",substr(hash,1,16),"\\1"),canonical,perl=TRUE)
    dest<-file.path(directory,versioned)
    if(!file.exists(dest)||!identical(unname(tools::md5sum(dest)),hash))if(!file.copy(path,dest,overwrite=TRUE))stop("Could not version browser asset.")
    replacement<-paste0(sub('=".*','',match),'="',versioned,'"')
    html<-gsub(match,replacement,html,fixed=TRUE)
    rows[[canonical]]<-data.frame(canonical,file=versioned,md5=hash)
  }
  if(!length(rows))return(invisible(character()))
  html<-paste0(html,"\n")
  before<-paste0(paste(readLines(index,warn=FALSE,encoding="UTF-8"),collapse="\n"),"\n")
  if(!identical(html,before))writeBin(charToRaw(enc2utf8(html)),index)
  assets<-do.call(rbind,rows);rownames(assets)<-NULL
  manifest<-file.path(directory,"cache-assets.json")
  json<-as.character(jsonlite::toJSON(list(schema_version=1L,assets=assets),dataframe="rows",auto_unbox=TRUE,pretty=TRUE))
  if(!file.exists(manifest)||!identical(paste(readLines(manifest,warn=FALSE),collapse="\n"),json))writeLines(json,manifest,useBytes=TRUE)
  swc_cache_validate_app(directory)
}

swc_cache_validate_app <- function(directory) {
  index<-file.path(directory,"index.html")
  if(!file.exists(index))return(invisible(character()))
  html<-paste(readLines(index,warn=FALSE,encoding="UTF-8"),collapse="\n")
  if(!grepl("\\.swc-[a-f0-9]{16}\\.(js|css)",html))return(invisible(character()))
  manifest<-jsonlite::read_json(file.path(directory,"cache-assets.json"),simplifyVector=TRUE)
  assets<-manifest$assets
  if(!identical(manifest$schema_version,1L)||!is.data.frame(assets)||!nrow(assets)||
      !all(c("canonical","file","md5")%in%names(assets))||anyDuplicated(assets$canonical))stop("Invalid browser asset manifest.")
  for(i in seq_len(nrow(assets))) {
    row<-assets[i,]
    if(!grepl("^[A-Za-z0-9_.-]+\\.(js|css)$",row$canonical))stop("Invalid canonical browser asset path.")
    expected<-sub('(\\.(js|css))$',paste0(".swc-",substr(row$md5,1,16),"\\1"),row$canonical,perl=TRUE)
    paths<-file.path(directory,c(row$canonical,row$file))
    if(!identical(row$file,expected)||!all(file.exists(paths))||!all(unname(tools::md5sum(paths))==row$md5)||
        !grepl(paste0('="',expected,'"'),html,fixed=TRUE))stop("Missing, stale or unlinked versioned browser asset.")
  }
  referenced<-regmatches(html,gregexpr('[A-Za-z0-9_.-]+\\.swc-[a-f0-9]{16}\\.(js|css)',html,perl=TRUE))[[1]]
  if(!all(referenced%in%assets$file))stop("Unverified versioned browser reference.")
  invisible(c("cache-assets.json",assets$file))
}

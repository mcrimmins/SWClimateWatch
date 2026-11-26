# Bounded convenience loop. Re-source to resume; a source failure stops the loop.
source("scripts/load-daily-explorer-wy2026.R")
wy2026_max_batches<-getOption("swc.wy2026.max_batches",200L)
if(length(wy2026_max_batches)!=1L||is.na(wy2026_max_batches)||!wy2026_max_batches%in%1:500)
  stop("Choose 1-500 WY2026 batches.")
for(wy2026_i in seq_len(wy2026_max_batches)) {
  message("WY2026 batch ",wy2026_i,"/",wy2026_max_batches)
  wy2026_batch<-run_wy2026_explorer_batch(month=getOption("swc.wy2026.month",NULL),
    download=isTRUE(getOption("swc.wy2026.download",FALSE)),
    max_input_dates=getOption("swc.wy2026.max_input_dates",10L),
    max_end_dates=getOption("swc.wy2026.max_end_dates",7L))
  if(wy2026_batch$status%in%c("ALL_RELEASES_PRESENT","MONTH_READY") &&
     (!is.null(getOption("swc.wy2026.month",NULL))||wy2026_batch$status=="ALL_RELEASES_PRESENT"))break
}
message("Batch loop finished. Run scripts/test-daily-explorer-wy2026.R for full validation before navigation assembly.")

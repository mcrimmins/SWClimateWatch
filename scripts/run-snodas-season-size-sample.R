# Five representative WY2024 dates to measure archive and grid sizes.
# This is a bounded sample, not the complete October-May bootstrap.
source("R/config.R")
source("R/snodas.R")
source("R/audit-snodas.R")
source("R/snodas-inventory.R")
source("R/snodas-bootstrap.R")

snodas_size_sample_dates <- as.Date(c(
  "2023-12-15", "2024-01-15", "2024-02-15", "2024-03-15", "2024-05-15"
))
snodas_size_sample_plan <- plan_snodas_cool_season(2024L)
snodas_size_sample_plan <- snodas_size_sample_plan[
  snodas_size_sample_plan$date %in% snodas_size_sample_dates, , drop = FALSE
]
if (nrow(snodas_size_sample_plan) != length(snodas_size_sample_dates)) {
  stop("A size-sample date is not listed in the WY2024 inventory.",
       call. = FALSE)
}
download_snodas_plan(snodas_size_sample_plan)
for (index in seq_along(snodas_size_sample_dates)) {
  date <- snodas_size_sample_dates[index]
  process_snodas_date(date, c("swe", "depth"))
  message("Checked SNODAS SWE and depth ", date)
}
snodas_size_sample <- data.frame(
  date = snodas_size_sample_dates,
  raw_mb = round(file.info(vapply(snodas_size_sample_dates,
                                   snodas_archive_path, character(1)))$size /
                   1024^2, 1),
  swe_mb = round(file.info(vapply(snodas_size_sample_dates,
                                   snodas_processed_path, character(1),
                                   variable = "swe"))$size / 1024^2, 1),
  depth_mb = round(file.info(vapply(snodas_size_sample_dates,
                                     snodas_processed_path, character(1),
                                     variable = "depth"))$size / 1024^2, 1)
)
print(snodas_size_sample, row.names = FALSE)

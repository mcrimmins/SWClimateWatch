# No downloads or publication. Fit coefficients and maps are cached separately.
source("scripts/load-prism-monthly.R")
source("R/map-reference-layers.R")
source("R/map-product-scales.R")
source("R/map-southwest.R")
monthly_spi_pilots <- build_prism_monthly_spi_pilots(
  durations = getOption("swc.monthly.spi.durations", c(1L, 3L, 6L, 12L)),
  force = isTRUE(getOption("swc.monthly.force.spi", FALSE)))
print(monthly_spi_pilots$summary, row.names = FALSE)
print(monthly_spi_pilots$results, row.names = FALSE)
if (monthly_spi_pilots$summary$status != "READY") stop("Some SPI pilots failed; inspect last-batch.csv and rerun.", call. = FALSE)
message("Local SPI gallery: ", monthly_spi_pilots$gallery)

source("scripts/load-prism-monthly.R")
monthly_spi_methods <- validate_prism_monthly_spi_methods()
print(monthly_spi_methods, row.names = FALSE)
if (any(monthly_spi_methods$status != "PASS")) stop("SPI method validation failed.", call. = FALSE)

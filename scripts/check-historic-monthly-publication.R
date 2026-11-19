source("scripts/load-historic-monthly-publication.R")
print(validate_historic_monthly_publication(rendered = !"--source-only" %in% commandArgs(TRUE)), row.names = FALSE)

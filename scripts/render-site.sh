#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

Rscript R/update-data.R
Rscript scripts/build-map-product-site.R
Rscript scripts/validate-map-products.R
cd "$project_dir/site"
quarto render
cd "$project_dir"
Rscript scripts/validate-map-products.R --require-rendered

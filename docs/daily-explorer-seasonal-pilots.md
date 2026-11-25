# Daily Explorer seasonal checks

Local checks before expanding WY2025. These use the July benchmark's shared
builder and validators, with separate diagnostic roots and release markers.
No site, publication, scheduler or permanent environment changes are included.

| Window | Viewer dates | Weather support dates | Expected maps |
| --- | --- | --- | --- |
| Winter | February 1–7, 2025 | January 3–February 7 | 49 PRISM, 21 daily weather, 42 weather means |
| Late-June comparison | June 24–30, 2025 | May 26–June 30 | 49 PRISM, 21 daily weather, 42 weather means |

Late June is a candidate quiet-weather comparison, not a claim of no hazards,
heat or storms. Review the measured precipitation, temperature departures,
reports and hazards before accepting it as the quiet case. Winter is also a
seasonal test, not a preselected guarantee of a snowstorm.

Each viewer has the same precipitation, temperature, daily/7-/30-day weather,
report and hazard controls as July. Means always require all supporting dates.
Reports include the preceding UTC day for precipitation-map timing; hazard
coverage and timelines are checked for the entire selected window.

The laptop input audit found all 21 PRISM date/variable layers per window.
June can reuse 29 verified July weather markers, leaving seven support dates;
winter needs 36 dates. Markers reference shared GRIB files, without copying
those files or changing the accepted July release. Reuse is conditional on
source/index checksums. Missing fields require explicit download permission.

Run from RStudio at the project root:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
options(swc.seasonal.download = TRUE)

# At most ten additional supporting dates per window per call.
# Four passes are sufficient for 36 supporting dates, barring source failures.
for (batch in seq_len(4)) {
  source("scripts/prepare-daily-explorer-seasonal-pilots.R")
  if (all(seasonal_inputs$status == "READY")) break
}
stopifnot(all(seasonal_inputs$status == "READY"))

# Uses cached weather inputs; the download option permits the initial
# storm-report and NWS hazard archive requests as well.
source("scripts/build-daily-explorer-seasonal-pilots.R")
stopifnot(all(seasonal_build$status == "READY"))

options(swc.seasonal.download = FALSE)
source("scripts/test-daily-explorer-seasonal-pilots.R")
source("scripts/preview-daily-explorer-seasonal-pilots.R")
```

Interrupted preparation/rendering can resume by rerunning the corresponding
script. An incomplete build has no verified release marker and cannot preview.
The render limit defaults to all seven endpoints per window. Set
`options(swc.seasonal.max_end_dates = 2L)` for smaller render batches, then rerun
the build until both status rows are READY. This limit affects weather renders;
the PRISM builder independently reuses verified map caches.

Previews: winter at <http://127.0.0.1:8802/>, late June at
<http://127.0.0.1:8803/>. Both servers are started by the preview script.

Outputs live under `data/diagnostics/daily-explorer-seasonal-pilots/`:

- `input-summary.csv`, `build-status.csv`, `validation-summary.csv` summarize both windows.
- Each window has `input-plan.csv`, `weather-progress.csv`, `build-summary.csv`,
  `run-history.csv`, `storage.csv`, `review-coverage.csv`,
  `terrain-input-coverage.csv` and `viewer/window-release.json`.
- The validation summary includes regional precipitation summed across the
  seven days and the average regional daily mean-temperature departure.
  Missing summary values stay missing; they are not replaced by zero.
- Storage categories describe working copies and shared selected inputs;
  adding categories or windows can double-count shared files. Viewer size is
  disk size, not the browser's initial download. Run history separates
  preparation from rendering/event assembly; build-summary time is only the
  latest build call.

Review winter map values and wind screening; 30-day windows that begin in the
preceding month; report noon/UTC timing; sparse or zero reports versus missing
coverage; hazard type filters and structured details; both timeline rows;
and linked maps, tables and narrow-screen behavior. Compare workload and
payloads with July before planning resumable monthly WY2025 batches.

Implementation checks passed locally: July's 103 checks and 70 seasonal checks,
plus unchanged July release validation. Seasonal downloads, completed map
renders and visual acceptance remain pending the commands above.

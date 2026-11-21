# Full-record station custom-date pilot

Approved November 20: selected-station custom dates over its full locally cached
record, with efficiency assessment before staging/daily integration. The
existing Station Conditions page, its map/table presets and daily runner remain
unchanged. No station downloads, publication or operational cache edits occur.

Run in laptop RStudio:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/build-station-custom-dates-pilot.R")
source("scripts/check-station-custom-dates-pilot.R")
source("scripts/preview-station-custom-dates-pilot.R")
```

Optional repeat-build and copied-cache append/revision measurements:

```r
source("scripts/benchmark-station-custom-dates-pilot.R")
source("scripts/benchmark-station-custom-dates-updates.R")
```

The preview serves `data/diagnostics/station-custom-dates-pilot` on
`http://127.0.0.1:8784/`. It safely reuses an existing matching pilot server;
another service on that port is not stopped. Choose another port with
`serve_station_custom_dates_pilot(port = 8785)`. The build's folder lock prevents
overlapping jobs. RStudio must remain open to serve the preview.

## Data and behavior

All 62 cached station/ThreadEx records are included. Each station index states
its own first/last date and data cutoff; the verified laptop snapshot ends
November 3, 2026. Missing or flagged observations remain unavailable. Trace
precipitation retains explicit status and zero measured inches. High-below-low
temperature pairs are flagged using the existing station-chart screening.

Precipitation is a complete period total only when every requested day is
eligible; otherwise it is an explicitly labeled observed subtotal. Temperature
means require eligible high/low pairs and show paired-day coverage. Extremes
describe the selected period, not historical records. Full-resolution selected
daily data can be exported to CSV. Arbitrary-period historical ranks, normals
and anomalies are not supplied by this first pilot.

Dates, metadata and summaries are independent of the existing map/table presets.
No whole-network custom-date map has been added. Historical station moves,
component changes or missing days are not treated as a homogeneous trend series.

## Efficiency design

- A small station catalog loads first. Selecting a station fetches its index;
  annual observations wait for a requested date range.
- Annual JSON filenames include content hashes. Station/index fingerprints
  invalidate revisions, including revisions with an unchanged ending date.
- Four annual files load concurrently. The application retains at most 24 annual
  files plus the active selected period in a worker. It never loads historical
  data for all stations into the browser at once.
- The browser worker computes summaries/CSV, keeping full-record calculations
  off the interface thread. Charts use at most 600 intervals. Long-range
  precipitation bars are interval totals and temperature lines are paired-day
  interval means; original daily resolution remains in statistics and CSV.
- Unchanged source caches reuse all verified chunks. Changed station caches are
  fingerprinted by year; only affected years are rewritten. Date signatures
  normalize integer/double storage so appending dates cannot invalidate otherwise
  identical historical years. Obsolete generated JSON is pruned only within the
  station's diagnostic output folder.

## November 20 measurements

Laptop first export: 62 records, 5,948 annual chunks, 569 seconds, zero requests.
Total annual payload: 32.49 MiB; catalog: 12.74 KiB; largest annual file: 7.66 KiB.
Steady unchanged repeat build: 9.50 seconds, zero chunks rebuilt.

Copied-cache simulations sampled 25-, 87- and 151-year records. An appended
missing day rebuilt exactly three current-year chunks and reused 260 historical
chunks in 10.55 seconds; an older precipitation revision rebuilt exactly three
affected historical chunks in 9.20 seconds. These are three-record sample
measurements, not a full-network new-date or production VM benchmark. Source
caches were not modified.

Desktop localhost browser measurements (application cache cleared per case;
HTTP cache may respond; bytes are uncompressed annual JSON sizes):

| Selection | Payload | Elapsed | Worker | Chart rendering |
| --- | ---: | ---: | ---: | ---: |
| Anvil Ranch, 365 days | 9.86 KiB | 190 ms | 2.7 ms | 2.1 ms |
| Anvil Ranch, 84 years | 464.67 KiB / 85 files | 4.40 s | 41.6 ms | 2.7 ms |
| Yuma Area, 151 years | 804.06 KiB / 151 files | 8.10 s | 115.9 ms | 5.0 ms |

Repeating the same full-record range made zero requests and repainted in
2–3.5 ms. The main full-record cost is request count, not chart calculation.
The Performance review disclosure runs reproducible short/annual/decade/full
cases in the user's browser. Raw reports are saved in the diagnostic pilot folder.

R screening/cache tests passed (24 assertions). Every payload passed integrity,
calendar and status checks, and browser-model summaries matched independent R
summaries for 248 real station/range cases. Node checks include leap days,
one-day/missing observations, reversed bounds, trace/flag handling, overlapping
chunks, display bounds and CSV formula safety. Interactive browser checks passed
date selection, reversed-range rejection, a historical leap-day window, station
switching, and full-record worker rendering. Automated capture of the CSV
download stalled; the CSV generator is tested, but browser download verification
remains manual. Phone/throttled-network tests were not completed.

Before daily integration: review the pilot, benchmark a full-network new-date
run on the VM, test a real narrow/phone/throttled connection, verify CSV download
in a normal browser, and decide whether multi-year bundles would reduce the
151-request full-record case. Preserve fast preset startup and lazy history;
do not put this in the daily runner until those results are reviewed.

# RCC-ACIS station inventory pilot

This is a research audit for a possible station-based section of Southwest
Climate Watch. It does not change the website, daily update, or deployment.
The goal is to identify long, sufficiently complete daily temperature and
precipitation records before choosing stations or designing anomaly, rank, or
extreme-index products.

## Run from the project root

```r
source("scripts/audit-acis-stations.R")
swc_acis_inventory_result$shortlist
```

The default run audits at most **five new stations**. Repeating the same command
continues with the next unaudited stations. To increase the cap for one run:

```r
Sys.setenv(SWC_ACIS_MAX_STATIONS = "20")
source("scripts/audit-acis-stations.R")
Sys.unsetenv("SWC_ACIS_MAX_STATIONS")
```

To refresh the discovery metadata before its seven-day cache expires, set
`SWC_ACIS_REFRESH_METADATA = "true"` for that run. Annual coverage summaries
are reused within the same completed calendar year and automatically become
pending when a new calendar year is completed. The per-station summaries are
small; full daily station series are **not** saved by this audit.

Outputs are local, ignored by Git, under
`data/diagnostics/acis-stations/`:

- `metadata-screen.csv`: all discovered stations, metadata dates, coordinates,
  and the preliminary candidate flag.
- `station-shortlist.csv`: selected candidates, audit state, and annual
  completeness counts by variable.
- `annual-coverage/<ACIS uid>.csv`: observed and missing days for each completed
  calendar year and each of `maxt`, `mint`, and `pcpn`.

## Discovery and screening

Two ACIS `StnMeta` requests are merged by unified station ID: one for Arizona
and New Mexico, and one for the existing AZ–NM map bounding box (including the
border pad). The state request is necessary because **ThreadEx area records
often have no point coordinates** and therefore do not appear in a bounding-box
query. ACIS identifier type `9` marks ThreadEx. These records remain in the
audit, but they cannot be put on a station map until a defensible display
location is supplied separately. A ThreadEx record is a composite area series,
not an ordinary fixed observation site.

All ThreadEx records enter the shortlist. Other stations enter if ACIS
metadata shows at least 70 years of date span for each of maximum temperature,
minimum temperature, and precipitation, with an endpoint within two years of
the audit date. This broad first-pass threshold is **not** a completeness
claim; date range alone can conceal long gaps. The shortlist is intentionally
larger than the eventual public station set, so geographic balance and
station-history review can follow the objective coverage audit.

## Completeness method and interpretation

For each shortlisted station, one compact `StnData` request asks ACIS for
calendar-year reductions with `mcnt` (missing-day count) for all three
variables, from the first metadata year through the last completed calendar
year. Annual coverage is `(days in year - missing days) / days in year`, with
leap years handled explicitly. The station table counts years with at least
90% observed days over the available history, within 1991–2020, and in the
latest ten completed calendar years. The 90% cutoff is a **screening metric**,
not a decision that incomplete years are safe for every later calculation.
Daily extremes and exact 7/30/90-day totals will require stricter
period-specific checks, trace/flag handling, and quality review.

The audit does not yet resolve station moves, instrument changes, ThreadEx
component changes, observation-time bias, or metadata geocoding. It does not
compute climate rankings or compare stations to PRISM. Station selection should
also consider spatial coverage, long-term continuity, and variable-specific
fitness—not just the largest number of complete years. Only completed years
are scored; current-year timeliness is visible in the metadata end-date columns
but is not counted as an annual completeness year.

## Next decision after the audit

Review the audited shortlist by AZ/NM and surrounding border area, select a
manageable, geographically balanced pilot set (including ThreadEx and a few
fixed stations), then inspect **daily** data and provenance for those stations
before specifying the first public table/map product. Keep the station pilot
separate from the daily publish workflow until those checks pass.

ACIS API definitions: [station metadata and identifier types](https://docs.rcc-acis.org/acisws/#i-stnmeta),
[station data, annual reductions, and missing counts](https://docs.rcc-acis.org/acisws/#ii-stndata).
ThreadEx context: [RCC Threaded Extremes](https://threadex.rcc-acis.org/).

# Development roadmap

Planning review: October 25, 2026. This is the consolidated backlog, not a
commitment to enable every candidate product. No production settings change
when this document is edited.

## Operational baseline

The October 23 production release is commit
`55ba6a79a7a0d199302b56c5c9a7d5975e12157b`. It includes the Daily Explorer,
Station Conditions, and Current Snow's observed SWE, absolute departure,
percent of median, and exact seven-day net change when available. Historical
peak-SWE and snow-covered-day maps are published; seasonal snow anomaly
companions remain local pilots. The public Methods page reflects this release.

The reported staging run took 53m 48s with changed inputs; the subsequent
production run took 11m 40s with no PRISM or Daily Explorer rebuilds. These are
different workloads, not a controlled performance comparison. Laptop changes
must still be tested, committed, staged on the VM, and explicitly promoted.

## Agreed additions and enhancements

| Workstream | Next bounded step | Relative effort |
| --- | --- | --- |
| Historical snow anomaly companions | Validate seasonal peak-SWE departure and percent-of-median pilots, then stage all eligible WY2005-WY2025 years. Retain coverage and support guards and existing archive cautions. | Moderate |
| Raster plotting warnings | Locate affected builders and correct the rendering geometry without altering climate statistics. Compare before/after maps. | Small-moderate |
| Daily-update speed | Profile several consecutive new-date runs, cache-hit/miss behavior, costly PRISM reference work, and station processing. Benchmark before removing products or changing cadence. | Moderate |
| SNODAS source revisions | Define a bounded recheck policy for already processed archives, provenance changes, and affected reference/map invalidation. | Moderate |
| Completed-year Daily Explorer | Decide what remains public at water-year rollover, then test dated manifests, navigation, retention, storage and rebuild costs before historical backfill. | Moderate-large |
| Station metadata and additional extremes | Scope station/component history and historical extremes comparisons. Any additional formal indices need explicit periods, thresholds, completeness, ties and baseline definitions. | Variable |
| Station custom date periods | Assess a start/end-date selector alongside presets, initially bounded to the recent daily data already published. Separate basic summaries from historical comparisons; benchmark map/table recalculation, lazy loading, payload size and browser responsiveness before implementation. | Moderate; full historical comparisons substantially larger |
| Shared city-label styling | Consider the smaller Daily Explorer labels for other maps; review representative precipitation, temperature and snow backgrounds before a site-wide rebuild. | Small-moderate |
| Station audit maintenance | Establish a repeatable full-record audit refresh cadence, visible audit age and automatic cautions; avoid a manual station-by-station approval requirement. | Moderate |
| Product freshness visibility | Distinguish successful publication from stale or quality-held individual products in console/ntfy summaries. Set source-specific lag thresholds rather than requiring identical dates. | Small-moderate |
| Internal documentation reconciliation | Replace obsolete manual/unpublished/two-snow-map descriptions or clearly mark them as historical pilot instructions. Preserve useful reproducibility details. | Small |
| ENSO/RONI composites and analogs | Define season, variable, reference and sample membership before implementing configurable comparisons. | Large |
| Validated SPI module | Separately validate fitting, zero precipitation, reference period and SPI-1/3/6/12 behavior; do not substitute raw standardized precipitation anomalies. | Large |
| Daily weather and circulation diagnostics | Explore a minimal upper-air/wind complement to the existing PRISM maps; compare NOAA CORe and ERA5 data access, latency, usefulness and daily cost. See the scope below. | Small scoping pilot; integration estimate pending |
| Archived forecast discussions in Daily Explorer | Links-only MVP implemented locally October 26: date-bound core/adjacent-office AFD and WPC searches. Pending user review and staging; metadata indexing and optional SPC/report sources remain future work. | Local review/staging next; indexing effort pending |

## New exploration: daily weather and circulation

See [daily weather and circulation scope](weather-circulation-scope.md).
**Deferred October 25, 2026:** resume only when the user selects this project
again. The scope document contains separate scoping and implementation
checklists; no automatic follow-up or development is scheduled.
Requested uses include precipitation occurrence/patterns/extremes, temperature
patterns/extremes, wind events, at least a 500-mb map, subtropical jet extension
and summer monsoon-high position. Reuse the existing precipitation/temperature
products instead of creating another competing observation stream by default.

First evaluate a handful of winter storms, summer monsoon regimes, heat events
and wind episodes locally. NOAA CORe is the first candidate to benchmark, not a
settled selection. ERA5 is a comparison/historical-analysis candidate. No new
downloader, climatology backfill, public Atmosphere section or scheduled job is
authorized by this planning entry.

## New exploration: archived forecast discussions

See [discussion archive scope](forecast-discussion-scope.md) for feasibility,
source links and separate scoping/implementation checklists. This future item
can proceed independently of circulation-map downloads. The links-only panel was
implemented locally October 26 at the user's request; it adds no scheduled
downloads and is not yet deployed. It uses explicit UTC issuance-day searches
with clear forecast-versus-observation labeling. Exact-issuance metadata and
optional SPC/report products remain separate follow-ups.

## New exploration: Station Conditions custom date periods

Requested October 25, 2026; scoping only, not active implementation. See
[station period-selector scope](station-explorer-prototype.md#future-scope-custom-date-periods).
A bounded recent-date selector is feasible in principle without new climate
downloads, but arbitrary-period ranks/anomalies are not available from the
currently published preset results. Preserve the fast default preset view;
do not publish full station histories or precompute every possible date range.

## Suggested sequence

1. Finish and publish seasonal snow companions, unless a different feature is
   explicitly selected next.
2. Investigate plotting warnings and measure operational performance.
3. Run a small isolated weather/circulation feasibility pilot when selected;
   agree on maps, date semantics and a measured daily cost before integration.
4. Address source revision/freshness policy and station audit maintenance.
5. Schedule larger archive, composite, station-index and SPI projects separately.

Keep the operational daily publisher stable while experiments run locally.
There is no current storage-driven reason to discard the VM staging cache:
the user's latest VM report showed 192 GB free on /home.

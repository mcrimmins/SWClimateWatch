# AZ/NM NWS hazard pilot

Local retrospective assessment only. It does not modify the Daily Explorer,
site navigation, staging, production, cron or the daily runner.

## Run from the project root in RStudio

```r
source("scripts/build-nws-hazards-pilot.R")
source("scripts/test-nws-hazards-pilot.R")
source("scripts/preview-nws-hazards-pilot.R")
```

Preview: <http://127.0.0.1:8797/>. The first build fetches two bounded AZ/NM
shapefile responses per case: events starting during the review period and
events already active at its beginning. Four 30-day cases cover the local
Explorer's latest cached date, spring, monsoon and winter. These are comparison
periods, not a claim that spring is necessarily quiet or that any period is the
regional maximum. Full county boundaries are downloaded for measurement, then
geometry is deduplicated and simplified by 150 meters for display.

The viewer has case/date controls, 1/7/30-day windows, UTC or precipitation-map
timing, AZ/NM region filters, severity level, every returned hazard type, search,
active-during-window or effective-start-during-window selection, a map, pinned
details, paginated linked table and counts of unique events whose mapped bounds
intersect the viewport. Overlapping hazards remain individually selectable in
the table. Full NWS source text is linked from each event rather than downloaded
for every polygon. Missing geometry remains distinct from an empty hazard list.

Hazard types have stable colors across cases, shared by polygon boundaries/fills,
side-panel count buttons and table swatches. Warning boundaries are solid,
watches dashed and advisories dotted; text labels always identify both type and
level. The side-panel All types button resets hazard type and level filters while
preserving date, window, region, search and map extent.

## Coverage and event rules

Source: [IEM VTEC WWA archive](https://mesonet.agron.iastate.edu/request/gis/watchwarn.phtml)
and [backend contract](https://mesonet.agron.iastate.edu/cgi-bin/request/gis/watchwarn.py?help).
No phenomenon/significance whitelist is used. This includes all VTEC hazard
types returned for AZ/NM, not every NWS text product. Special Weather Statements,
routine forecasts/discussions and non-VTEC outlooks need separate sources.
Display-name definitions follow [pyIEM VTEC terminology](https://github.com/akrherz/pyIEM/blob/main/src/pyiem/nws/vtec.py);
unknown codes retain an explicit code-based label instead of being dropped.

An event is keyed by VTEC year, issuing office, phenomenon, significance and
event number. Geometry pieces and revisions are retained without increasing the
event count. Where a storm-specific polygon is available for an event, its county
representations are omitted from display. County/fire-weather/forecast zones
otherwise remain mapped. County-state membership comes from UGC codes; storm
polygons use spatial intersection with AZ/NM boundaries.

Storm geometry uses POLY_BEG/POLY_END intersected with ISSUED/EXPIRED. County
records use the archive's resolved issue/expiration intervals. Early endings
are therefore respected where reflected in the archive, but a complete history
of each county/zone extension and bulletin is not reconstructed. Source status
codes can reflect later lifecycle updates; the display is never live status.
The carry-in endpoint itself only searches the preceding 30 days. An ongoing
event that started earlier may be absent; this source limitation is displayed.
Resolve that limitation before claiming exhaustive long-duration flood coverage.

All selections use half-open UTC intervals. Precipitation timing ends at 12 UTC
on the selected map date; calendar timing ends at the following midnight.
Selections extending before the fetched case are labeled partial windows.
The view is retrospective; it is not a current public-warning service.

## Workload and caching

Outputs: `data/diagnostics/nws-hazards-pilot/`.

- `workload.csv`: per-case requests/reuse, archive bytes, download/read and
  processing time, raw rows versus events, repeated versus unique geometry,
  original/display vertex counts, metadata size/gzip estimate and geometry bytes.
- `view-workload.csv`: event/segment/geometry counts and geometry JSON bytes for
  each date at 1/7/30 days, using UTC windows clipped to fetched coverage. This
  identifies busy views rather than relying only on the final day.
- The browser's Workload assessment disclosure adds device-specific filter,
  load and draw timing, uncached geometry requests and decoded JSON bytes.
  These exclude basemap tiles and are not a heap-memory measurement.

Raw, checksummed responses: `data/raw/nws-hazards/az-nm/`. Processed geometry and
metadata caches: `data/processed/nws-hazards-pilot/`, keyed by input checksums,
normalization code and label definitions. Unchanged cache reuse avoids geometry
reprocessing. Browser metadata loads by case; geometry loads on demand for the
selected window/filter in at most 16 per-case geometry bundles, with six
concurrent requests and in-session reuse. Bundles may include boundaries outside
the selection to avoid hundreds of tiny requests. Only matching areas are drawn.

Rerun the build to assess cache reuse:

```r
first_run <- nws_hazards_pilot$summary
source("scripts/build-nws-hazards-pilot.R")
cached_run <- nws_hazards_pilot$summary
print(first_run)
print(cached_run)
```

The caches are reused by default, including recent data. For an explicit source
revision check, use `options(swc.hazards.refresh=TRUE)` before building and reset
it to FALSE afterward. This pilot has no automatic daily refresh/retry policy;
those are separate integration work. Failed downloads stop the assessment rather
than presenting unavailable data as zero hazards.

## Acceptance before integration

November 22 local measurements: the four cached archive pairs total about
54.7 MiB. Per-case metadata is approximately 169–744 KiB before compression
(23–103 KiB gzip estimate); complete display geometry is approximately
1.3–1.9 MiB per case. After processed-cache reuse, all four builds together took
about 8.4 seconds, with zero source requests. These are local measurements, not
VM promises or a daily incremental-update benchmark. The first verified build
mixed existing source caches with new downloads; it is not a complete cold-network
timing baseline. Timestamped workload CSVs preserve subsequent runs.

Browser review initially exposed too many small geometry requests. Bundling
reduced requests to at most 16 per case. A 238-event week loaded/drew in about
1.0 second in the review browser, including roughly 2 MiB decoded geometry.
Phone-width review confirmed the page stays within its viewport after correcting
the date-control sizing. Browser timing varies with selected window/device/cache.

Verify broad hazard types and both area representations; compare individual
events, timing and early endings with source history. Check carry-in and partial
windows, map/table selection, busy 30-day views and narrow screens. Review actual
cold/reused workloads before selecting operational retention, geometry packaging
and refresh caps. Fix source coverage gaps before staging; no deployment is
authorized or performed by these scripts.

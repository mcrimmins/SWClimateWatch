# Archived forecast discussions in Daily Explorer

Status: **links-only MVP implemented locally October 26, 2026**, following the
user's request to resume. No downloader, scheduled task, text index, production
deployment or full-text archive is added. Pending user review and VM staging.
The circulation-map project remains deferred and independent.

### Embedded-reader follow-up (local, October 26)

At the user's request after reviewing staging, primary selection now opens the
same dated archive search in a fixed-height, internally scrollable iframe:
520 pixels on desktop, 420 on narrow screens. The selected product is highlighted,
the reader header repeats its date, and Close reader removes its source URL.
Changing the selected map date also clears the reader; unrelated metric/view
changes preserve it without reloading. Modified clicks and an explicit new-tab
link retain external access.

The frame has no source URL until selection, uses an empty sandbox (no scripts,
forms or top navigation), and sends no Referer. Browser selection makes a direct
request to IEM, not to a new server-side downloader. No climate payload, map
cache or publishing request changes. A sample IEM response returned no
X-Frame-Options or Content-Security-Policy framing restriction, and the live
local browser displayed and scrolled the archived Phoenix text successfully.

An iframe error event displays a fallback message when the browser emits it;
that event cannot reliably detect all remote outages, empty results or framing
blocks. The fallback link and explanation therefore remain visible at all times.
No inspection of the cross-origin frame or claim of verified availability is
made. Local unit tests cover lazy loading, modified clicks, product changes,
state retention and clearing/closing. This follow-up still needs staging review.

## Implemented first-release decisions

- Collapsed panel beneath the selected map/grid, before Notable days. Five core
  AFD offices, five optional surrounding offices, and five WPC product families.
  Source mappings are small constants in `scripts/daily-explorer-assets/explorer.js`.
- Link searches use IEM's documented retrieve endpoint in HTML mode: selected
  UTC date 00:00 inclusive through next UTC date 00:00 exclusive, oldest first,
  explicit limit of 100. The product's own issue/valid times remain in the
  external original text; no metadata or availability is inferred locally.
- All archive targets update on date selection, arrows, timeline/notable selection or
  thumbnail changes. Seven-/30-day grids do not change the discussion period
  to the whole grid. AZ/NM summary selection does not suppress office links;
  national products are explicitly not spatially filtered.
- Searches are labeled as searches. Empty archives, non-issued event products,
  incomplete histories and product corrections are described. The panel
  distinguishes issue date, forecast validity and PRISM reporting periods.
- No archive request, prefetch, AI summary or server query is triggered by
  rendering or opening the panel. Selecting a product loads the sandboxed
  reader; its new-tab fallback uses `rel="noopener noreferrer"`.
  External availability cannot block publication.
- Only the existing HTML/JS/CSS assets change. No daily JSON schema, climate
  statistic, cache signature, image count, R downloader or map renderer changes.
- Local browser review confirmed the panel layout, new-tab link behavior and
  UTC link updates when stepping between September 30 and October 1. The preview
  is `data/diagnostics/daily-explorer/`; `discussion-links-preview.png` records
  the reviewed layout. Local preview climate dates reflect the laptop cache.

Validation recorded October 26, 2026:

- Read-only HTTP requests for October 23, 2026 returned 200 and matching product
  text for PSR/TWC/FGZ/ABQ/EPZ, VEF/SGX/GJT/PUB/AMA, and WPC PMDSPD/PMDEPD/
  QPFERD/FFGMPD/QPFHSD. This is a sample availability check, not a guarantee for
  every date. WPC-issued text is served via IEM rather than assuming WPC's own
  archive paths are reliable for automated access.
- `node tests/test-daily-explorer-ui.cjs` covers UTC search bounds, leap days,
  month/year rollover, invalid dates/products, all groups, new-tab safety, empty
  selection, navigation updates, and absence of new browser fetch calls.
- Focused R tests cover Daily Explorer, staging and the daily publisher. Review
  the local browser preview before approving a release; archive indexing,
  polygon filtering, report/SPC groups and generated summaries remain future work.

## Purpose and proposed first version

Add a collapsible **Forecast discussions for this date** panel below the selected
Daily Explorer map. Link forecaster reasoning to the precipitation, temperature
and wind patterns being examined without implying that a forecast is a verified
account of what occurred. Keep the original office, source, issue time and product
identity visible. Start with outbound archive links, not automated summaries or
a local full-text archive.

Suggested groups:

- **Local NWS discussions:** AFDs from offices serving the selected region.
  Candidate core offices: Phoenix (PSR), Tucson (TWC), Flagstaff (FGZ),
  Albuquerque (ABQ), and El Paso/Santa Teresa (EPZ). Confirm product IDs, office
  coverage boundaries and cross-state service areas during the pilot. Offer
  adjacent offices where relevant rather than treating state boundaries as
  forecast-office boundaries.
- **National weather context:** WPC short-range and extended discussions;
  excessive-rainfall, mesoscale-precipitation and heavy-snow discussions when
  relevant and available. Verify active product codes and historical changes;
  do not assume an old product listing proves continued issuance.
- **Optional event context:** SPC convective/fire-weather outlook discussions
  and mesoscale discussions, then NWS local storm reports or public information
  statements as a separately labeled observations/reports group. CPC extended
  outlook reasoning is a later climate-context option, not a daily diagnosis.

The panel follows the selected **single date**, even when the seven-/30-day grid
is open. Selecting a thumbnail changes the discussion date too. Retain an
explicit date label so the panel cannot be mistaken for a discussion of the
entire grid. An office selector can start with the displayed AZ/NM region;
spatially filtering national event products requires actual footprints, not just
a keyword match or issuance-office coordinates.

## Feasibility findings and sources

- IEM archives NWS text and supports date/product queries, metadata discovery,
  and retrieval of identified products. Its documentation warns that archive
  coverage varies historically; do not promise discussions for every mapped day.
  IEM is an external archive of NWS-issued text, not the issuing agency.
- IEM's retrieve service accepts UTC start/end timestamps and product IDs; the
  documented start is inclusive and end exclusive. Its default result limit is
  one, so a future discovery job must explicitly handle multiple issuances and
  truncation. A "latest" URL without date bounds is not an archived-day link.
- WPC lists short/extended, rain and snow discussion families. Its archive
  coverage and paths must be tested per product and date. Direct WPC/SPC page
  requests returned 403 in this research environment; search-index visibility
  is not proof of reliable programmatic retrieval. Do not bypass access controls.
- IEM also provides event-geometry services for WPC mesoscale precipitation
  discussions. Treat event products separately from routine daily discussions;
  absence can mean no issuance, missing archive data or failed retrieval.
- Current NWS services are a possible recent-data source, not an assumed
  full-history archive. Verify retention for each text-product endpoint rather
  than applying the observations/alerts retention rules to all products.

Primary documentation checked October 25, 2026:

- [IEM NWS text archive overview](https://mesonet.agron.iastate.edu/nws/text.php)
- [IEM office/product/date listings and coverage notes](https://mesonet.agron.iastate.edu/wx/afos/list.phtml)
- [IEM AFOS retrieval parameters](https://mesonet.agron.iastate.edu/cgi-bin/afos/retrieve.py?help=)
- [WPC discussion families](https://www.wpc.ncep.noaa.gov/html/discussions.php)
- [WPC short-range discussion archive](https://www.wpc.ncep.noaa.gov/archives/discussions/pmdspd/)
- [IEM WPC mesoscale precipitation geometry archive](https://mesonet.agron.iastate.edu/request/gis/wpc_mpd.phtml)
- [SPC product archives](https://www.spc.noaa.gov/archive/)

## Time matching and interpretation: scope before implementation

- Decide whether initial links mean **issued on the selected UTC date**, issued
  during an explicitly displayed Arizona-day window, or **valid for the mapped
  period**. These are different selections. Do not infer a product's valid period
  solely from its issue date; one discussion can cover several forecast days.
- Show issue time in UTC, with a clearly labeled local conversion if useful.
  Account for office-local daylight saving time rather than assuming every
  Southwest office follows Arizona time.
- PRISM reporting dates do not universally equal local midnight-to-midnight
  days. Initially label discussions as nearby-date context; define any stronger
  observation-window association before claiming exact correspondence.
- Provide multiple issuances or a dated archive-list link; do not silently pick
  the last discussion after an event and present it as the advance forecast.
  An optional "before the event" view needs a defined cutoff. Comparing forecast
  expectations with observed maps must avoid hindsight selection.
- Preserve corrections/amendments, stable archive/product identifiers, source
  links and issue times. IEM notes identifiers are not always unique; verify
  duplicate handling with headers/content hashes if building a local index.
- AFDs and WPC discussions contain forecasts, uncertainty and areas beyond the
  map. They are context, not event attribution, warnings verification or proof
  that a teleconnection caused an observed outcome. Reports remain preliminary
  observations unless independently verified.

## Efficient implementation options

1. **Links-only MVP — recommended starting point:** construct bounded office/
   product/date archive-search links in the browser from a small configuration.
   No daily text download, map rebuild or archive backfill. Label these as
   searches, not confirmed available products. Verify date encoding and filters.
2. **Small cached metadata index — optional next increment:** retrieve issue
   times and exact product links only for newly added/recent dates, in bounded
   requests by office/product group. Persist the index, deduplicate corrections,
   report truncation and recheck a short recent window for delayed arrivals.
   Benchmark rather than promise a particular runtime. No giant history crawl.
3. **Full text or excerpts — later, only if justified:** fetch on a controlled
   build schedule, cache by verified product identity/content hash and render as
   escaped text, never execute archive HTML. Confirm attribution/usage terms.
   Do not assume arbitrary cross-origin browser fetches will work. Preserve the
   full original source link and clearly distinguish excerpts or summaries.

Archive failures must not block PRISM/station/snow publication. A missing index
can fall back to dated search links with an honest availability message; never
redirect a historical date to today's discussion. Keep counts of unavailable,
failed and unqueried products distinct. No AI-generated summary in the MVP.

## Resume checklist

### Scope and sample review

- [ ] Agree on core offices, adjacent-office behavior, WPC products and whether
  optional SPC/report sources belong in the initial release.
- [ ] Choose examples from a winter storm, monsoon rain, heat and wind event.
  Test archive searches and identified-product links for several issue times,
  corrections, midnight boundaries, missing products and an older mapped date.
- [ ] Set issue/valid-time semantics and geographic relevance rules; confirm
  relevant office/PIL/WMO identifiers instead of generating guessed URLs.
- [ ] Review a static date-linked panel mockup with real archive links. Choose
  links-only versus cached metadata, and set runtime/request/storage budgets.

### Implementation after approval

- [x] Add configurable source/office mappings and date-bounded link generation.
- [x] Wire the panel to date/thumbnail changes without changing map statistics.
- [ ] If indexing is approved, implement bounded incremental discovery, stable
  provenance, correction handling, cache reuse, retries and graceful fallback.
- [ ] Test UTC/local boundaries, multi-day validity, multiple issuances, empty
  archives, malformed text/metadata, encoding and external-link safety.
- [x] Document archive limitations and date interpretation in the explorer and
  Methods page; add source attribution and appropriate new-tab behavior.
- [ ] Test locally, then promote a pinned release through VM staging. No
  production integration until the user approves the feature and staging result.

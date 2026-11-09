# Conditions synopsis: first increment

Scoped November 4, 2026. This is a local development plan, not an enabled daily
product or authorization to begin paid API calls. See the prioritized
[development roadmap](development-roadmap.md#priority-order-and-working-sequence).

## November 9 local increment: linked evidence and snow context

Implemented locally for review; not yet staged or promoted. The template now
writes a human-readable supporting page for every quantitative selected bullet.
These pages retain the exact periods, values, denominators, references and
station comparison support used in the prose. Related current-product links are
separate and explicitly may show newer dates. Publication copies the supporting
pages into a dated, content-addressed `synopsis-evidence` resource directory and
validates their checksums before sync. Synthetic review cases remain excluded
from publication.

The seven-day temperature departure is calculated from existing cached daily
PRISM inputs. Its supporting page includes a matching seven-day departure map;
it no longer relies on a generic Daily Explorer link to substantiate a weekly
mean. The map is reused when its source and rendering signature are unchanged.
If the map cannot be generated, the weekly temperature claim is withheld.
A diagnostic `highlight-link-audit.csv` records supported and withheld bullets.

Snow is summarized over AZ/NM only, using paired SWE/depth screening and verified
source/reference checksums. A current endpoint must be on or before the synopsis
cutoff and at most two days older. Storage comparisons use date-specific
WY2005–WY2025 centered-five-day medians of at least 1 inch and at least 18
reference years. They describe the fraction of eligible terrain below 75% or
above 125% of median; current zero SWE remains eligible so deficits are retained.
Desert cells with low typical SWE do not dilute these fractions.

Seven-day changes require exact endpoints. Their footprint includes normally
snowy cells or cells with at least 0.1 inch at either endpoint; gains/losses use
0.25 inch. Both summaries require at least 500 km² of eligible terrain and 98%
valid area. Missing endpoints are not zero. Contrasting gains/losses or deficits/
surpluses are disclosed when both cover at least 20% of the eligible area.
Thresholds are configurable in `config/conditions-synopsis.yml`.

Winter storage gets a regular opportunity even without a strong tail signal.
Other seasons require a supported spatial signal; change highlights require at
least 20% of eligible area. June–September remain inactive. Early-season change
can appear while storage ratios are withheld. At most three bullets per section
are selected; snow competes with existing temperature/station context. New data
and source revisions update evidence; unchanged data are not forced into a new
story. Previous-publication comparisons retain their existing success-only
anchor, and the supporting page includes the prior values when a change is
claimed. AI remains deferred.

Local review commands:

```r
source("scripts/build-conditions-synopsis-draft.R")
browseURL(normalizePath("data/diagnostics/conditions-synopsis/synopsis.html"))
source("scripts/review-conditions-synopsis-snow.R")
source("scripts/review-conditions-synopsis-seasons.R")
browseURL(normalizePath("data/diagnostics/conditions-synopsis/seasonal-review/index.html"))
```

The existing 24 fictional weather cases are complemented by seven snow cases:
winter deficit/surplus, spring loss, initial fall snow, missing data, small
reference area and inactive summer. No downloads, API calls or publishing are
performed by these review scripts. Real cached examples retain their actual
cutoff date, which may be older than today's production data.

## Current decision — November 5, 2026

Proceed with the deterministic template synopsis. AI interpretation, selection
comparisons and the proposed unlisted daily AI page are **deferred** at the
user's request. Retain the local experiments and review findings as reference;
do not integrate them into daily publication or schedule further API requests.
The ordinary template builder has no API dependency, even if an experimental
API environment switch is present. No credentials or private environment files
are changed by this decision.

Keep the reviewed two/three-bullet sections, seasonal selection, conditional
formatting, station eligibility rules and regional highlight candidates.
Relationship-led explanatory text may be revisited as deterministic wording;
the AI introduction remains an experiment, not part of the active template.

Next template milestones, in order:

1. Add supported regional snow context with reference-area and coverage guards.
2. Compare changes and event novelty with the last **successful publication**,
   rather than the current local-preview history.
3. Prepare the standalone template page, publication validation and fallback,
   then benchmark the added work on VM staging before production promotion.

**Staging implementation:** Home now has Maps (default) and Synopsis tabs, with
the same selected template content at `pages/synopsis.html`. The common deploy
path stages cached evidence before rendering, validates both rendered copies
and their dates/status, and advances a destination-specific synopsis comparison
snapshot only after a successful non-dry-run S3 sync. Same-date revisions compare
with that last successful snapshot; incompatible baselines/water years reset
the comparison. A failed evidence build publishes an explicit waiting notice
rather than unmarked older prose and does not advance the climate baseline.
The production display excludes review candidates, synthetic cases and AI prose.

Initial staging is intentionally limited to the reviewed precipitation,
temperature and station template, with a link to Current Snow and an explicit
note that regional snow narrative is pending. Staging performance measurements
and actual VM publication still need to be collected. Deployment commands are
in [Synopsis staging release](synopsis-staging.md).

The AI sections later in this document record historical experiments and possible
future work; they do not override this active decision.

**Production display decision:** show selected synopsis bullets only. The
template renderer defaults to `show_review_candidates = FALSE`; candidate
statements remain in diagnostic JSON for audit and selection checks. The local
seasonal review gallery explicitly opts into the candidate panel. This display
switch does not change selection, evidence or the published bullet budget.

## Purpose and page layout

Help a visitor understand the past seven days, past 30 days, water year so far, and meaningful
changes since the last successful publication, then follow links to the
supporting maps and station tools. Lead with hydroclimate and regional contrasts.

Prototype a separate, directly linkable **Conditions Synopsis** page first.
After content review, offer a Home **Maps / Synopsis** tab or a short synopsis
preview linking to the page. Keep placement separate from the data/narrative
trial so a layout change does not require rewriting the calculations.

Initial output: roughly 200–350 words, up to seven concise bullets including at
most two station highlights, grouped into three sections:

1. Past seven days: recent rainfall coverage/events, temperature and supported
   station extremes (two or three bullets when evidence permits).
2. Past 30 days: precipitation/temperature patterns and meaningful regional
   changes (one or two bullets).
3. Water year so far: precipitation progress, seasonal freeze/snow context and
   persistent deficits/surpluses (one or two bullets).

Attach supporting map/tool links directly to bullets. Embed supported changes
in the relevant period instead of adding a fourth section. Avoid describing one
event repeatedly; longer-period bullets should add context rather than repeat
the event's dates and station values.

Show generated time and each source's actual data-through date. The primary
PRISM period ends at the latest verified complete PRISM set, not today's date.
An update with no material change should say so briefly. Do not fill the maximum slots
with weak findings or repeat the same rain signal in several sections.

## Seasonal priorities and transitions

Keep the same core structure and evidence definitions year-round, but change
which supported facts receive space and emphasis. The following date ranges are
configurable editorial defaults, not inferred onset/ending dates or new climate
season definitions. Use each fact's observation date and period, not just the
publication date, when applying seasonal context.

| Editorial period | Main questions and emphasis | Guardrails and transition behavior |
| --- | --- | --- |
| Winter: December–March | Are recent precipitation and water-year accumulation above/below their matching references? Is mountain snow storage building or declining? Highlight supported SWE departure/percent of median, exact seven-day change, cold/warm departures and station freeze-night context. | Give snow a regular opportunity for a headline, including a supported lack of snow where substantial snow is normally present. Require eligible mountain/reference support; do not require current snow cover to describe a deficit. Net SWE gain is not snowfall. |
| Spring: April–May | How much precipitation and snow storage remain, and how quickly is modeled SWE changing? Emphasize lingering storage, gains/losses, recent warmth and precipitation deficits; station late freezes can be notable. | Gradually reduce snow emphasis as eligible storage and useful reference coverage diminish. Retain an unusual late storm or substantial remaining snow signal. Describe net loss without attributing it solely to melt, warmth or runoff. |
| Early summer transition: June 1–14 | Summarize recent dryness/warmth, water-year context and supported local rainfall. Link to completed-season snow summaries when useful. | Current snow monitoring ends with the configured October–May season and June closeout. Do not present the last May map as current June snow conditions or infer snow-free conditions from an inactive source. |
| Summer/monsoon context: June 15–September 30 | Where has rain occurred, how widespread or localized was it, and how do recent totals compare with the matching reference? Balance wet days and dry intervals, station wettest-day/multi-day observations where available, and heat/warm-night context. Preserve water-year deficits despite recent rain. | These dates select editorial emphasis, not a diagnosed monsoon onset or withdrawal. Daily regional means can hide local storms; include eligible station examples and rainfall-coverage metrics without demanding broad regional rainfall first. Rain observations alone do not establish flash flooding, storm severity or impacts. |
| Fall: October–November | Explain the new water year's early precipitation, recent storm patterns, temperature transitions, first freezes and initial snow where meaningful. In September, allow this transition context alongside summer priorities. | Early water-year rankings can be sensitive to small totals: show dates and amounts with percentile context and avoid extrapolating to the full year. Snow is optional while the reference median is small; emphasize observed SWE/absolute departure rather than unsupported ratios. |

Seasonal weighting changes selection priority, not factual eligibility or the
meaning of wet/dry and temperature labels. Let supported unusual conditions
override the usual order: a major spring snow signal can lead, while a dry or
warm winter need not manufacture a snow-growth narrative. Preserve AZ/NM
contrasts and avoid one fixed mountain location standing for the whole region.

Keep the past-30-day and water-year summaries as the initial common anchors.
Season-to-date totals for cool season or monsoon may be added only when cached
data, explicit start/end definitions and matching historical comparisons are
available; do not relabel a rolling 30-day metric as a seasonal total. Describe
dry intervals or additional heat indices only when the underlying metric and
its eligibility rules are implemented. Missing optional seasonal metrics should
reduce the summary gracefully rather than trigger new downloads or API guesses.

Configure seasonal priorities, optional metric IDs, date ranges and headline
limits in YAML. Keep climate thresholds/reference definitions in the metric
registry and version changes. Record the selected editorial period in evidence
metadata. A calendar transition by itself must not count as a climate change
or cause repeated headlines; do not compare reset season totals to the previous
season. Distinguish an inactive source, missing data and a measured zero.

## First evidence inventory

The unit of evidence is a verified numeric fact, not a PNG interpretation.
Use a small registry independent of which six maps are currently on Home.
Initially support combined AZ/NM plus each state; named subregions are deferred.

| Evidence family | First metrics | Existing basis / additional work |
| --- | --- | --- |
| Seven-day conditions and recent events | Area-weighted rainfall totals, temperature departures and daily rainfall mean/coverage, plus screened seven-day station extremes | Implemented from existing daily PRISM inputs, cached temperature normals and the station tool's seven-day summaries/details. No downloads or new climatology builds. |
| 30-day precipitation amount | Area-weighted mean inches; area receiving at least 0.10 inch | Read the existing date-matched 30-day accumulation grid; add the synopsis adapter and per-state masks. No new download or climatology. |
| 30-day precipitation context | Area below P33 / above P67; P10 / P90 tails for very dry / very wet wording | Existing percentile grids and dashboard summary logic; calculate explicit configured tails without averaging pixel percentiles. |
| 30-day temperature | Area-weighted mean-temperature departure, in degrees F | Existing 30-day departure grid and summary logic; retain 1991–2020 reference and state contrasts. |
| Water-year precipitation amount | Area-weighted total since October 1 | Existing water-year accumulation grid; a new lightweight regional summary adapter is needed. Do not call this station precipitation or percent of annual normal. |
| Water-year precipitation context | Area in the below-/above-normal percentile tails | Existing water-year percentile grid and dashboard adapter; label the matching season-to-date comparison. |
| Notable recent day | One newly available wettest regional-mean day, with rainfall coverage; optional broad warm/cold day | Existing Daily Explorer numeric daily summaries. Compare only among available eligible dates in the stated window; not a historical record. |
| Station observations | At most two supported selected-period extremes or unusual ranks, with station, exact dates and sample size | Existing screened station summary CSV/detail data. Use fixed stations for network counts; ThreadEx can be a separately identified example. Freeze-night departures are optional seasonal detail. |
| Seasonal snow | SWE-covered area and supported exact seven-day gain/loss context | Existing verified observed/change grids. Agree the snow threshold, region masks and useful denominators before regional aggregation. Skip unsupported ratios and avoid dilution of mountain signals by desert area. |

Freshness/coverage is mandatory metadata for every family, rather than an extra
climate headline. Weather maps and RONI can be linked as context in this first
version, but automatic circulation interpretation and ENSO attribution are not
included. Recent-period weather means and anomaly baselines remain separate
roadmap work. A combined regional synopsis must not suggest it describes all
parts of both states uniformly.

Implementation findings: `map_dashboard_summaries()` already caches selected
Home metrics, currently for combined AZ/NM with a 98% valid-area gate. Its visible
configuration does not provide every proposed metric or state breakdown.
`daily_explorer_summary()` already has AZ/NM/combined daily summaries but uses
a 95% minimum coverage by default. Preserve those source definitions; record
actual support and apply the synopsis's explicit eligibility rule instead of
silently treating the two thresholds as identical. Use 98% area support for
new synopsis regional grid statements; withhold lower-support candidate facts.

## Candidate highlight rules for review

These are proposed editorial thresholds, not newly enabled scientific
classifications. Keep thresholds in configuration and align labels with the
existing map categories. Review them on actual evidence before enabling them.

1. **Broad wet/dry pattern:** emphasize the P33/P67 tail when it covers at least
   50% of a region, with stronger wording at 67%. Say which region and fraction.
2. **Mixed pattern:** if both tails cover at least 25%, describe the contrast
   instead of selecting whichever side is slightly larger. State-level results
   can identify where the contrast occurs.
3. **Very wet/dry areas:** optionally highlight P10/P90 coverage of at least
   10%, stronger at 25%. Describe that fraction as very wet/dry; do not label
   the entire region that way or equate area fraction to regional return period.
4. **Recent temperature:** describe departures beyond +/-0.5 F, emphasizing
   magnitude at +/-3 F. This is a departure cue, not a statistical-significance
   or record claim. Opposite AZ/NM signs should not disappear in the pooled mean.
5. **Short versus seasonal context:** connect a wet recent period with a still
   dry water year only when both independently meet their support/label rules.
   Do not announce improvement solely because the two different periods differ.
6. **Material change:** nominate a tail-area change of at least 10 percentage
   points, a 30-day mean-departure change of at least 0.5 F, or a category
   transition meeting a persistence/rounding guard. Avoid flickering labels
   from small threshold crossings. Tune after reviewing test snapshots.
7. **New rainfall event:** nominate a newly available daily observation when
   at least 25% of a region received 0.10 inch. This describes broad rainfall,
   not damage, flooding or climatological rarity. Rank against the available
   recent window only; do not repeatedly present the same date as new.
8. **Station context:** only use explicitly eligible comparisons with their
   period and sample size. Separate a wettest day in the chosen 30-day window
   from a highest corresponding 30-day total in the usable historical sample.
   Limited-sample cautions remain visible; no unqualified all-time record claim.
9. **Snow relevance:** mention a verified storage/change signal during the
   operational snow season, with eligible dates and meaningful spatial support.
   Set minimum gain/loss extent after inspecting cached examples. Never report
   net SWE change as snowfall, or low-median/unavailable pixels as zero percent.
10. **No change / insufficient data:** report no material change or identify
    the missing evidence. Prefer omission or a short limitation to speculation.

Select findings by scientific relevance, spatial support and novelty. Cap
duplicates and retain opposing signals rather than forcing one regional story.

## Evidence contract and change accounting

For each fact retain: stable ID, metric/product ID, numeric value and units,
geography/mask version, start/end dates, reference definition, valid coverage or
sample size, quality status/reason, source signature, input version and approved
destination link. Lower bounds must be a separate value type, not ordinary
totals. Link IDs resolve through local code; do not accept invented URLs from
a model. Validate whether date/station deep links are actually supported;
otherwise link to the correct tool/page with written selection guidance.

Store a snapshot only as **published** after the S3 workflow reports success,
using the existing application's success semantics. Keep previous and candidate
snapshots distinct. Until a previous compatible published snapshot exists,
withhold change claims and label the comparison baseline as not yet available.
Failed or interrupted publishing and identical-input reruns must not advance it.
Reset or explicitly explain comparison across water-year rollover, changed
metrics/masks or methods; do not subtract values with incompatible definitions.

Distinguish changes from newly observed days, late/revised reports, and the
effect of entering/leaving days in rolling periods. Do not promise an exact
causal decomposition from summary snapshots alone: it needs overlapping daily
source versions. If attribution is unavailable, use neutral wording such as
"the updated 30-day map shows..." and disclose that revisions/window movement
may contribute. Keep changes in data coverage out of climate-change claims.

## Template versus hybrid comparison

Build the evidence adapter, selection rules and template first. The template
is the comparison baseline and the fallback that can ship independently.
Prototype on three to five real cached snapshots if the retained inputs allow;
include contrasting wet/dry/mixed cases without downloading an archive just
for prose. Use clearly identified synthetic fixtures for unavailable cases,
early water year, revisions, inconsistent dates and no-change behavior.
Historical reconstructions must be labeled as reconstructed with current
source versions, not claimed to be the exact information published on that day.

For an optional API trial, give the model the **same selected evidence** as
the template, with a fixed length/structure and supporting fact IDs. Do not let
it browse, recalculate ranks, infer unsupported impacts or invent causes. Use
local numeric/date/link insertion where possible. Keep structured output
validation separate from scientific correctness. Compare drafts for:

- Correct values, signs, dates, geography, units and comparison periods.
- Unsupported claims, especially records, trends, causation and impact language.
- Useful synthesis, readable prose, balanced contrasts and helpful navigation.
- Behavior with missing/partial/stale data, revisions and unchanged reruns.
- Seasonal usefulness: winter snow growth and deficits; spring loss and late
  snow; June closeout with inactive current snow; localized summer rain and
  heat; fall first freezes/snow and early water-year interpretation. Test
  September/October and other editorial boundaries, periods straddling them,
  opposite AZ/NM signals, and an out-of-season supported event. Use real cached
  examples where available and clearly labeled fixtures otherwise.
- Input/output usage, latency, retry behavior and reproducibility/provenance.

Only add API use if the prose is materially more useful with no loss of factual
reliability in the trial. Model selection and paid calls require a subsequent
implementation decision. The earlier token-cost examples are planning
illustrations, not a measured daily operating cost.

## Performance and release gates

- No new source download or climatology build in this increment. Reuse cached
  grids, daily summaries and screened station values; cache masks and fact
  signatures independently of prose and Home layout.
- Benchmark evidence extraction on a new-input and unchanged-input run. Initial
  target: under 30 seconds of added cached-data processing on the VM, with a
  substantially cheaper unchanged rerun. This is a target to test, not a promise.
- Generate static HTML and compact evidence files. Keep any future API key on
  the VM; never expose it in published/browser assets.
- A missing fact, optional API error or invalid generated response must not
  block the main climate publication. Render current eligible template facts
  and explicit unavailable sections; never reuse an undated old narrative.
- Local review of numbers, links, labels and contrasting snapshots; staging
  review and a daily/cache rerun before explicit production promotion.
- Decide Home placement after the content comparison. API, weather-circulation
  diagnosis, detailed subregions, impacts, forecasts and archives remain outside
  this first implementation.

## Immediate next deliverable

A local evidence-inventory report showing which of the above facts can be
produced for one cached snapshot, their exact dates/coverage, approved links and
estimated computation cost. Review a short template draft from that inventory
before finalizing thresholds or making external API calls. Include a seasonal
coverage matrix showing which candidate metrics already exist for each period,
which need a lightweight cached-data adapter and which remain deferred. Review
short winter, spring, summer and fall examples before staging the first release;
one current November snapshot is not enough to establish year-round behavior.

## Local evidence pilot: November 4

The first evidence builder is implemented; it is not connected to publication.
From the project-root R console:

```r
source("scripts/build-conditions-synopsis-evidence.R")
View(synopsis_evidence$facts)
# Optional: inspect a specific cached date, including missing-input diagnostics.
snapshot <- build_conditions_synopsis_evidence("2026-10-05")
```

To catch up the laptop's inputs first, then automatically rebuild the inventory:

```r
source("scripts/refresh-conditions-synopsis-inputs.R")
View(synopsis_refresh$evidence$facts)
```

This separate opt-in refresh makes network requests. It follows the existing
PRISM revision/gap checks and yesterday/fallback validation, processes daily
inputs, and calculates only the five required derived grids. Its request budget
includes the whole catch-up queue rather than stopping at the normal 100-request
cap. Station caches/locally staged station assets are refreshed to the common
PRISM endpoint. Snow downloads are limited to that date and its seven-day prior
endpoint in the active season; full-domain archives are released after existing
pair verification. Optional station/snow failures are recorded, and their
unavailable evidence remains withheld.

The refresh does not render the Quarto site, regenerate the full map catalog,
send notifications or sync to S3. It retains the normal map-rebuild-pending
marker so a later full local update refreshes maps after these source changes.
See `refresh-summary.csv` for the endpoint, counts, elapsed time and optional
source errors. Do not run it concurrently with another laptop data update.

Output under `data/diagnostics/conditions-synopsis/`: `report.md`, `facts.csv`,
`station-examples.csv`, `evidence.json` and the regional evidence cache. A normal
run selects the latest shared cached date for all five PRISM grids; it does not
fetch newer inputs. Explicit dates can inventory incomplete snapshots. The
report shows snapshot age, exact periods, configured references, valid-area
coverage, quality status and map destinations. Public links can show newer maps
than the selected local snapshot; they do not select historical map versions.

The laptop pilot used October 5, 2026, yielding 39 supported regional facts
across AZ, NM and their combined area. A measured rebuild took 3.38 seconds and
an immediate regional-cache reuse took 0.23 seconds, before diagnostic writes;
these are laptop measurements, not VM guarantees. No station example matched
the same endpoint in the laptop's newer station summary, so it was withheld.
Snow pair/checksum availability is inventoried, but mountain/reference-based
regional snow metrics remain deferred. At this initial inventory stage, station
historical ranks, temperature/freeze adapters and notable-day selection were
also subsequent increments; the station-extreme extension below supersedes
the temperature/freeze limitation.

A subsequent user-requested laptop refresh on November 4 caught up the inputs
and reran the test through November 3. It downloaded/processed 108 PRISM grids
(including revisions), refreshed all 62 station caches to the same cutoff and
processed only the November 3/October 27 SNODAS pairs. Full-domain snow archives
were released after verification. Total refresh time was 25m 14s; this includes
the month-long catch-up and station calculations, not just synopsis processing.
The refreshed evidence had 39/39 regional facts available, 39 eligible fixed
station rainfall examples before the two-example cap, and a verified seven-day
snow endpoint pair. The evidence-only rebuild took 1.94 seconds; an immediate
cached rerun took 0.50 seconds. No Quarto render or S3 publication occurred.

Seasonal priorities and thresholds live in `config/conditions-synopsis.yml`.
Tests cover editorial boundaries/leap day, area weighting, percentile boundaries,
coverage/range rejection, grid time mismatch/missing inputs, station eligibility,
snow pair checksums and evidence-cache invalidation. No previous publication
anchor is advanced.

## Local template and station extremes

The local draft now includes five candidate station metrics: largest daily
precipitation, largest three-day precipitation, highest daily maximum, lowest
daily minimum and cool-season-to-date freeze-night departure. Each selected
value must match the dated station summary and complete usable daily detail;
event dates, three-day endpoints, ranges and maximum/minimum temperature
consistency are checked. Publication exclusions are respected. Historical
record cautions remain attached; the draft notes them when present.

Freeze counts require complete minimum-temperature data for their full stated
season-to-date period, a matching count/departure and at least 15 usable
1991–2020 reference years, consistent with Station Conditions. The default
highlight floor is three nights of departure. The configuration can raise the
sample requirement. It cannot lower it below the existing 15-year gate.
Hot-day/warm-night threshold counts and historical rankings of individual
extremes remain deferred; no new historical extreme comparisons are inferred.

Default selection uses fixed AZ/NM stations, at most two distinct stations, with
season-specific metric order. After the first choice it prefers a complementary
metric family and state where eligible evidence exists. It orders values only
within the same metric; inches, degrees and nights are never compared as one
numeric severity score. These are illustrative station observations, not a
claim to the regional network's largest event. Zero rainfall is not an event
highlight, and incomplete/flagged daily windows cannot qualify.

```r
source("scripts/build-conditions-synopsis-draft.R")
browseURL(normalizePath(synopsis_draft$path, winslash = "/"))
```

The script rebuilds evidence from cached inputs, then writes `synopsis.html`,
`synopsis.md`, `draft-evidence.json` and `station-extreme-candidates.csv` under
the diagnostic directory. `station-examples.csv` now contains the selected,
fully screened extreme facts rather than the original rainfall-only inventory.
Evidence schema version 2 includes all candidate/selected station extremes;
draft paragraphs carry supporting fact IDs and approved tool/map links. The
HTML escapes source text and works directly from a local file, without a server.

The November 3 draft selects Chama's 11 freeze nights (15.4 fewer than its
supported mean of 26.4, from 23 usable reference years) and Show Low Airport's
2.84-inch daily rainfall on November 1. It also summarizes the 30-day and
water-year PRISM facts. It explicitly withholds prior-publication change claims
and regional snow interpretation. Evidence processing with the new adapter
took 1.67 seconds on a cached laptop run; full draft time is not yet benchmarked
on the VM. No API call or publication hook is enabled.

Next: review the local draft for useful wording and length, exercise contrasting
seasonal fixtures, complete regional snow metrics and agree the publication
comparison anchor before staging. The HTML is a review artifact, not a live
Home tab or published synopsis page.

## Seven-day lead, bullets and local change tracking

The latest local increment uses the three bulleted period sections at the top
of this scope. It adds nine seven-day regional facts (rainfall mean/coverage and
temperature departure for AZ, NM and combined AZ/NM) and 21 daily rainfall
regional rows, calculated from the existing daily PRISM grids and cached
temperature normals. It does not download sources or build new climatologies.
Missing normals withhold the temperature result without inventing a value;
missing/low-coverage rainfall remains explicit. Intermediate grids and recent
summary caches live only in the diagnostic directory.

Seven-day station candidates require the station tool's matching `7day` rows,
publication screening and complete usable seven-day daily detail. They cannot
borrow a more extreme value from the 30-day window. Seasonal freeze-night
departures remain in the water-year section; they are not relabeled as weekly
counts. Selection keeps at most two station highlights across the whole draft,
with complementary metric/state preferences and no repeated station. Default
rain-event floors are 0.10 inch for a daily maximum and 0.25 inch for a three-day
maximum; these identify reportable observations, not historical rarity.

An initial weekly bullet gives regional precipitation and the wettest available
regional-mean day with rainfall coverage. Once comparison data exist, newly
available days can take priority over an older larger day when their mean rain
reaches 0.10 inch or at least 25% of the region receives 0.10 inch. Weekly
temperature or station observations complete the section without exceeding
three bullets. The 30-day and water-year bullets add matching percentile-area,
temperature or seasonal context, rather than repeat the same station event.

`scripts/build-conditions-synopsis-draft.R` now tracks a **local preview** history
in `preview-state.rds`, after successful diagnostic writes. This is independent
of production and never advances a successful-publication marker. The first
complete snapshot establishes the baseline; the next later date compares with
it. Same-date reruns preserve the same comparison rather than comparing against
themselves. Backward date previews do not overwrite newer history. Water-year
rollover and selection-configuration changes reset the comparison. Incomplete
core regional evidence does not advance the history.

Station novelty uses station ID, metric and event dates, not the moving window's
end date. An event already present among prior eligible candidates is not
reintroduced as new merely because the script reruns or its reported value is
revised. A genuinely new qualifying event can replace an older larger one.
Supported seasonal context can remain while recent event highlights change.

Material regional changes are attached to their existing period bullets:
initial thresholds are 10 percentage points of percentile-tail area or 0.5°F
of 30-day mean departure. The larger tail-area change is considered, not just
the currently dominant tail. Units, cutoffs, reference and mask versions must
match. Quiet wording requires complete comparable indicators, no newly selected
station event and no qualifying new broad rainfall day; it refers specifically
to percentile-area and temperature indicators, not an absence of all weather.
Any missing support prevents that quiet-day claim.

Comparison statements explicitly identify the local comparison date. Changes
can reflect source revisions and days entering/leaving a rolling window; they
are not attributed automatically to new precipitation, melt or another cause.
Source reporting intervals remain distinct. Production integration must later
replace this preview comparison with the agreed last-successfully-published
snapshot semantics and validation; that hook remains deferred.

Evidence schema version 3 adds `recent` and `station_week`. Diagnostic files
include `recent-facts.csv`, `recent-days.csv`, `station-week-candidates.csv` and
the explicitly named 30-day inventory files. The final `station-examples.csv`
and `station-extreme-candidates.csv` describe draft selection across the weekly
and seasonal pools. Draft JSON includes supporting fact IDs, prior values for
material changes and the dated comparison snapshot. Its signature ignores
generation time and cache-hit bookkeeping, so unchanged reruns remain stable.

The HTML places each statement and its supporting links in a bullet and keeps
reading notes collapsed. Tests cover seven-day versus 30-day eligibility,
novel-event replacement/repeat suppression, overall station caps, stable daily
comparisons, quiet/missing-data behavior, material changes, rollover and the
three-section layout. Continue seasonal content review and regional snow work
before staging; no API or production dependency has been added.

## Readable narratives and condition-driven station context

The current local draft formats prose dates as `Oct 28–Nov 3, 2026` and
`on November 1`, including both years when a range crosses January 1. Generated
times display in Arizona time. ISO dates remain unchanged in evidence, source
keys and comparison state; presentation never changes time-window calculations.

Station extremes now have direct historical context from the cached full daily
record. `R/conditions-synopsis-station-context.R` evaluates one matching window
per earlier endpoint year, using the same calendar end date and 7-/30-day
length. It calculates weekly daily-rainfall peaks, three-day maxima, high/low
temperature extrema and within-30-day longest dry runs. These are **not** ranks
of weekly precipitation totals or every daily observation in the record.
References exclude the current endpoint year and future years. Non-leap years
without February 29 are omitted for that endpoint; no date is fabricated.

Every extreme window must be complete, observed, in range and free of disallowed
flags/accumulations. Trace rain is handled consistently with the station tool.
Available maximum/minimum pairs cannot be inverted. The current full-cache
metric must agree with the already screened summary/detail value before context
can be attached. Existing publication exclusions and historical-record cautions
are preserved. A missing/stale/mismatched cache withholds context and prevents
an unsupported headline; it never triggers a download.

Defaults require 25 earlier complete windows for a rank, and 15 complete
1991–2020 windows for a reference mean/anomaly. Those gates match the existing
station comparison floors and can be raised. Displayed rank counts include the
current period once; ties and incomplete-record sample sizes are explicit.
Cold minima use ascending ranks and the corresponding lower-tail unusualness.
Temperature peak anomalies compare with the historical **window high/low**,
not with an ordinary mean temperature. All calculated context, including rain
peak anomalies, is retained in evidence even when prose uses only its rank.

The default unusualness gate is the directional 90th percentile of prior
matching-window extrema. Rain headlines also require at least 0.50 inch in a
day or 1 inch in three days, so tiny amounts do not lead solely because their
reference is usually dry. An unusual dry run must last at least 10 days and
is explicitly bounded by its 30-day analysis window; it is not necessarily an
ongoing or full-season spell. These are configurable editorial selection rules,
not hazard thresholds, return periods or formal drought classifications.

Weekly focus responds to observed conditions: rainfall, heat, cold, mixed
signals, quieter recent conditions/longer-term context, or insufficient support.
Supported station rarity and regional seven-day temperature/rainfall inform
the choice; the calendar now breaks ties rather than reserving a freeze slot.
Active weeks prefer context-supported recent extremes. Quieter weeks can use
unusual 30-day dry spells and supported seasonal freeze departures. Heat/cold
weeks lead with temperature; mixed weeks retain both regional signals.
Geographic/family preferences operate among near-ties in unusualness, rather
than forcing a much weaker example. Ties in rarity use metric priority and
within-metric magnitude; unlike units are not numerically compared.

The current November 3 example uses Flagstaff's 3.37 inches on November 1,
the highest weekly wettest-day amount among 97 complete matching periods
(96 earlier windows spanning 1893–2025, plus the current one), alongside
supported seasonal context. This does not establish an all-calendar-day record
or an observed flood/damage impact. Actual impacts remain outside this synopsis
until separately sourced report/hazard work is implemented.

Historical results use bounded per-station/window caches plus two aggregate
packets. Signatures include source content, endpoint, method and support gates;
historical source revisions invalidate them. The first historical pass took
69 seconds on the laptop; a new date can require a similar reference pass.
Unchanged cached runs subsequently took roughly 4–5 seconds. This is above the
original proposed 30-second target for a cold/new-date build; VM timings and
further profiling remain pending. No new source requests or browser-side
historical calculations were added, and the cache does not retain a separate
full history for every past date.

The final immediate cache-only checks took 1.81 and 1.70 seconds for evidence
processing; observed cached timings therefore range roughly 2–5 seconds.

Tests now cover current/future-year exclusion, source revision invalidation,
current-cache disagreement, flags/accumulations, complete-window support,
directional ranks and ties, readable/leap/cross-year dates, adaptive weekly
focus and dry-spell fallback.

### Seasonal template review

Run locally from the project root:

```r
source("scripts/review-conditions-synopsis-seasons.R")
browseURL(normalizePath(synopsis_seasonal_review$path, winslash = "/"))
```

The standalone gallery at
`data/diagnostics/conditions-synopsis/seasonal-review/index.html` contains 24
explicitly fictional cases: winter cold/quiet conditions, spring cold/dryness,
early-summer heat, widespread/localized monsoon precipitation, monsoon heat,
fall cold, October 1 rollover, opposing state temperatures, insufficient
evidence, leap day and a high absolute temperature with ordinary historical
standing, plus ten regional-highlight cases described below. Each case retains its synthetic evidence and draft JSON alongside
the readable preview. These are editorial fixtures, not historical hindcasts
or validation of real events.

All 24 template cases pass the expected-focus, station-selection, bullet-budget,
source-ID, readable-date and provenance checks. Additional tests protect the
real preview history: synthetic inputs cannot advance it. Individual synthetic
pages and Markdown explicitly identify their fictional inputs. The gallery
links separately to the observational cached-data preview when present.

The review produced two small editorial fixes: lead with unusual localized
station precipitation when the regional mean is small, and describe opposing
Arizona/New Mexico temperature departures explicitly rather than relying on
their combined mean. Precipitation wording includes the liquid equivalent of
snow; it does not imply rain alone.

Snow-active cases remain marked **PENDING** for regional snow interpretation.
The gallery does not infer a snow deficit, melt or snowfall from file presence
or from SWE changes alone. Next: define and validate supported regional snow
metrics, then compare against successful publications, benchmark on the VM,
and integrate into staging. No source downloads, paid API calls, site rendering
or publication are performed by this review script.

### Conditional formatting preview

The review gallery and cached-data HTML preview now emphasize at most two
phrases per bullet. Teal/brown indicate wetter/drier signals, orange/blue
warmer/colder signals; fewer freeze nights use the warmer color and more freeze
nights the colder color. Ordinary precipitation totals receive neutral bolding,
not a wetness classification from their absolute amount. Regional percentile
area phrases retain their explicit threshold; large spatial coverage is not
automatically labeled an exceptional percentile.

The `formatting` section of `config/conditions-synopsis.yml` controls the switch,
palette and magnitude gates. Defaults color regional temperature departures at
3 F and add bold color at 6 F; selected station comparisons receive stronger
emphasis at the 98th unusualness percentile. Supported freeze departures get
stronger emphasis at 10 nights. Material changes retain their separate existing
comparison thresholds and explicit higher/lower wording. These are presentation
choices, not new hazard classifications or changes to which facts qualify.

An initially collapsed color key explains the conventions. Exact plain prose
and supporting IDs remain in draft JSON alongside the emphasis metadata;
Markdown uses bold without relying on color. Snow colors will be added with
the supported snow metrics rather than inferred from the precipitation wording.

### Regional persistence, transition and station agreement

Three optional cached-input candidates now compete for companion Past 30 days
bullets, retaining the core precipitation summary and a maximum of three bullets:

- Persistence: area with at least six warm days (maximum above the daily 90th
  percentile) or cold nights (minimum below the daily 10th percentile) in the
  last 30 days. At least 20% of valid regional area is required. The count itself
  is not historically ranked, and six days is an editorial threshold.
- Transition: area whose rolling 30-day precipitation rank increased or
  decreased at least 20 percentile points in 14 days, requiring at least 20%
  spatial coverage. The prose explains window turnover and possible revisions;
  this is neither a rainfall amount nor a day-to-day publication change.
- Corroboration: fixed-station precipitation/mean-temperature percentiles above
  90 or below 10, requiring at least 30% of eligible stations, 10 eligible for
  AZ/NM or five for a state. Complete current observations, at least the
  configured 25 reference periods and publication screening are required.
  ThreadEx, ambiguous duplicates, stale endpoints and invalid/partial current
  windows are excluded. The numerator, denominator and state are explicit.

Breadth scores select the strongest qualified candidate across combined-region
and state summaries. They measure spatial/network breadth, not impact severity.
A selected dry-spell example competes with a 0.65 score; this is an editorial
priority, not a physical threshold. Network counts are inventories of eligible
stations, not land-area estimates; records differ among stations. No claim about
daily changes in the network fraction is made without a matched station set.

Thresholds are in `regional_highlights` in the synopsis YAML. Diagnostics retain
all three grid inventories, counts for 7/30/90-day station summaries where
eligible, and contributing station IDs/reference counts/detail checksums.
Only the 30-day station counts enter the new monthly prose. The local HTML
also has a closed review panel with the strongest qualified option in each
category, including candidates that did not win a main companion slot.

Missing matching-date map grids are unavailable, never replaced with older
maps. Normal evidence generation only reads caches. For the laptop pilot, build
the three optional grids explicitly from cached daily inputs and reference data:

```r
source("scripts/prepare-conditions-synopsis-highlight-grids.R")
source("scripts/build-conditions-synopsis-draft.R")
browseURL(normalizePath(synopsis_draft$path, winslash = "/"))
```

Preparation recalculates two temperature counts and the two endpoint ranks
needed for the 14-day difference. It makes no downloads or PNGs and does not
publish; missing underlying daily/reference caches stop preparation. Production
will reuse its normally generated matching-date grids after integration.

The November 3 cached-data preview selects a station-agreement example: 13 of
16 eligible New Mexico fixed stations (81%) have 30-day mean temperatures above
their 90th percentile. The prepared persistence and transition grids have full
regional coverage, but neither meets the default spatial trigger in this
snapshot; their statements are withheld rather than forced into the synopsis.
The strongest negative rank-change area is 18.5% of New Mexico, below the 20%
trigger. These are local pilot observations, not published synopsis content.

The same seasonal review script now also generates ten fictional regional
examples: warm-day persistence, cold-night persistence, improving and declining
precipitation ranks, wet/dry/warm/cold station agreement, three competing
highlights, and a withholding case. The index identifies the winning monthly
category. The competition example retains all three alternatives in its closed
review panel while using two distinct monthly companions (station agreement
and rank transition). The withholding
example verifies that a high percentage from only three eligible stations, or
a grid signal covering only 19% of the area, produces no supplemental bullet.

### Two/three bullets and optional AI editorial comparison

`maximum_section_bullets: 3` allows a useful third statement, without requiring
one. A strong monthly temperature departure can remain alongside a precipitation
transition; two competing temperature signals do not consume both companion
slots. Dry-spell context can also be retained as a distinct third point. Existing
seven-day and water-year sections retain their supported statements and stay
within three; evidence is not invented to fill a section.

The local API pilot currently tests **selection and ordering**, not free-form
rewriting. This deliberately narrower comparison helps assess editorial benefit
while locking every displayed number, qualifier, date and source ID to approved
statements. Numeric-only or schema validation cannot establish that arbitrary
AI prose is scientifically correct. Free-form phrasing remains a subsequent
experiment, requiring semantic review rather than an automatic accuracy claim.

Run an offline preview (zero API requests by default):

```r
source("scripts/compare-conditions-synopsis-ai.R")
browseURL(normalizePath(synopsis_ai_comparison$path, winslash = "/"))
```

Configure `OPENAI_API_KEY` privately in the user's `~/.Renviron`, outside the
repository, and restart R. Never paste the key into chat or save it in a project
script. Check presence without printing it:

```r
nzchar(Sys.getenv("OPENAI_API_KEY"))
```

Then opt into a single request for the current evidence:

```r
Sys.setenv(SWC_SYNOPSIS_AI = "true", SWC_SYNOPSIS_AI_MODEL = "gpt-4.1-mini")
source("scripts/compare-conditions-synopsis-ai.R")
browseURL(normalizePath(synopsis_ai_comparison$path, winslash = "/"))
Sys.unsetenv("SWC_SYNOPSIS_AI")
```

The model is configurable. The implementation uses the Responses API with a
strict JSON schema, `store=false`, a 60-second timeout and one request maximum
(no automatic repair/retry calls). It sends the compact approved statement
catalog and seasonal metadata, not raw station histories or local file paths.
The response contains statement IDs only. Local validation rejects unknown IDs,
wrong sections, duplicate topics, omitted supported coverage and excess bullets;
the renderer supplies the original wording, evidence links and formatting.
Unavailable credentials, request failures and invalid selections retain the
template with an explicit status. No synopsis publication hooks are enabled.

A bounded last-selection cache is keyed by the complete statement catalog,
prompt/schema and model. Unchanged enabled reruns reuse a validated selection;
they make no new API call. Changes in source wording/values, prompt or requested
model invalidate it. Disabling the API always shows the template, even if an AI
cache exists. A cached row's token counts describe the original request, not new
charges. Summary CSV retains requests, input/output tokens, runtime and status;
exact currency cost is left to the API usage dashboard rather than using stale
hardcoded prices.

Artifacts are under `data/diagnostics/conditions-synopsis/ai-comparison/`:
`comparison.html`, `request-preview.json`, `comparison-evidence.json` and
`summary.csv`. The side-by-side screen labels fallback output clearly, so an
offline/mock test cannot be mistaken for a live AI result. Tests use injected
responses to verify rejection, opt-in, cache reuse and fallback without charges.

Implementation references: [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs),
[GPT-4.1 mini model](https://developers.openai.com/api/docs/models/gpt-4.1-mini),
and [API key quickstart](https://developers.openai.com/api/docs/quickstart).

### Local interpretive-writing experiment

An additional mode now permits actual prose synthesis, rather than ID-only
selection. It asks the model to explain nested week/month/water-year context,
geographic contrasts, persistence versus new observations and important limits.
Every bullet cites supplied evidence IDs. The payload includes the approved
statement catalog plus available core/seven-day regional facts, rounded before
transmission; it excludes raw histories, credentials and local source paths.
Regional snow interpretation and unsupported impacts/causes remain out of scope.

```r
readRenviron(path.expand("~/.Renviron"))
Sys.setenv(SWC_SYNOPSIS_AI = "true")
source("scripts/compare-conditions-synopsis-interpretive.R")
browseURL(normalizePath(synopsis_ai_comparison$path, winslash = "/"))
Sys.unsetenv("SWC_SYNOPSIS_AI")
```

This makes up to one paid request per changed payload; unchanged successful
reruns use the cache. Outputs are separate under
`data/diagnostics/conditions-synopsis/ai-interpretive/`, preserving the selection
comparison. The mode permits 3,000 output tokens to accommodate the JSON and
six to nine narrative bullets. It remains disabled by default and has no
publication integration or unattended daily job.

Local screens enforce cited-source existence, section/bullet limits, plain
text, no repeated bullets and no numeric tokens absent from the cited evidence.
A conservative subject screen rejects some unsupported impacts/processes.
These are partial checks: matching a number to a cited source does not verify
its variable, direction, geographic interpretation or causal meaning. All
accepted prose is visibly labeled **AI-written, needs human review**, including
cached drafts. A review is required before any public-use decision.

Request or validation failures retain the template. Completed interpretive
responses are kept in `last-response.json` for diagnosing rejected drafts;
they are not published or treated as passed. Diagnostic summaries distinguish
request/validation failures, retain usage when a response was received and
never persist arbitrary HTTP error bodies or authentication headers.

The first live interpretive-writing test on November 5 used the November 3
snapshot and returned six narrative bullets (7,951 input / 1,107 output tokens).
It failed the cited-number screen. Manual inspection also identified grid-area
coverage described as station coverage, 30-day temperature evidence extended
to water-year scope, and fewer freeze nights interpreted as delayed first
freezes. These failures demonstrate that citations/structured output alone do
not establish scientific reliability. The accepted comparison retained the
template; the rejected prose is available locally in `rejected-review.html`
with an explicit warning. No AI-written synopsis was published.

The prompt was subsequently tightened on those specific scope errors and
inline citation IDs, without another paid request. The rejected response is
retained as a regression example; the revised prompt still requires a further
live evaluation. Tests cover unsupported numeric tokens, unknown citations,
blocked process topics, plain-text requirements and review labels, in addition
to the existing request/cache/fallback tests.

### Relationship-led "What stands out" pilot

A narrower local experiment keeps every template bullet unchanged and adds
one short qualitative introduction. R establishes up to three supported
relationships before an API request: recent rainfall within a wet month or
coexisting with dry water-year standing, a monthly temperature-anomaly contrast
between states (or same-direction weekly/monthly temperature departures), and
an early-water-year limitation where applicable. Matching dates, window starts,
available facts and comparable temperature references/units are required.

The initial editorial gates are a weekly regional precipitation mean of at
least 0.25 inch, at least 60% of valid area in the relevant monthly/water-year
percentile class, a two-degree difference between state temperature departures,
or weekly/monthly departures both at least three degrees in the same direction.
These are local interpretation rules, not new climatological classifications.
Nested windows do not establish what conditions were before the latest rain.
No change-since-publication relationship is generated without prior evidence.

The model receives only the bounded relationship scopes, approved meanings and
fixed quantitative anchors, rather than the broader metric inventory. It returns
one qualitative sentence per relationship; digits, extra numbers/units, unknown
relationship IDs and several unsupported topics are screened out. Numeric
anchors are inserted by R, never rewritten by the model. Scientific meaning
still requires human review; passing these screens is not a correctness guarantee.

```r
# Deterministic preview, no API request:
source("scripts/review-conditions-synopsis-stands-out.R")
browseURL(normalizePath(synopsis_stands_out_review$path, winslash = "/"))

# Optional live wording (unchanged successful input uses the bounded cache):
readRenviron(path.expand("~/.Renviron"))
Sys.setenv(SWC_SYNOPSIS_AI = "true")
source("scripts/review-conditions-synopsis-stands-out.R")
browseURL(normalizePath(synopsis_stands_out_review$path, winslash = "/"))
Sys.unsetenv("SWC_SYNOPSIS_AI")
```

The separate `ai-stands-out/` diagnostic folder retains `review.html`, the
relationship/evidence JSON, request preview, usage summary and last response.
API failure/rejection retains a visibly labeled rule-based introduction above
the template. A disabled API also shows rule-based text, not a purported AI draft.
The first live test on November 5 used three relationships from the November 3
snapshot, 554 input tokens and 121 output tokens, and took 3.29 seconds for the
API/review stage. Its prose passed local screens and was inspected for the
previous period/geography/ranking errors; it remains an experimental draft,
not evidence of unattended reliability or a production integration.

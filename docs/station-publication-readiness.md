# Station explorer publication-readiness audit

The station explorer remains an **unpublished research preview**. This screen
does not download data or deploy the site. It uses the explorer's latest saved
page data and the separately saved full-record daily-quality audit, then
refreshes the **local preview** with display cautions.

From the project root:

```r
source("scripts/audit-acis-station-publication.R")
table(swc_station_publication_audit$products$publication_status)
```

Outputs are in `data/diagnostics/acis-stations/publication-audit/`:

- `product-readiness.csv`: one station × period × map metric, including
  computed value, exact reason if unavailable, provenance date, and
  publication status.
- `station-quality-context.csv`: one station × variable family (`pcpn` or
  `tmean`), showing baseline/recent completeness, longest gaps, source-ID
  changes, flags, accumulated days, and cross-variable consistency checks.
  Mean temperature conservatively uses the poorer completeness and larger
  gap of `maxt` and `mint`. The consistency count is negative precipitation
  days for `pcpn` or days with maximum below minimum temperature for `tmean`.
- `readiness-summary.csv`: status counts by audience (mapped fixed station
  versus table-only ThreadEx series), period, and metric.
- `threshold-sensitivity.csv`: mapped-station counts under alternative
  normal and rank-comparison year cutoffs. This is diagnostic only.

The automatic rules are:

- Complete, unflagged periods display normally. If only the most recent one
  or two precipitation reports are missing (one for a 7-day period), the
  observed precipitation total displays as a provisional lower bound (`≥`),
  with `DISPLAY_CAUTION` and a dashed map edge. Its departure, percentile,
  and rank remain unavailable; the missing days are never treated as zero.
  Interior precipitation gaps, larger lags, and quality flags hide the total.
  A temperature mean with **98% or more** valid paired days and no gap over
  two consecutive days displays normally; at **95–<98%**, a partial result
  has `*`, `DISPLAY_CAUTION`, and a dashed edge. Below 95%, a longer gap, or a quality
  flag hides it. Stale caches are unavailable on the common page date; values
  are not silently carried forward or imputed.
- A departure needs at least **15** eligible 1991–2020 comparison years.
  A percentile/rank needs at least **25** earlier eligible matching periods.
  Historical precipitation periods must be complete; historical temperature
  periods use the same 95% paired-day and two-day maximum-gap rule.
  Below these floors, that product is unavailable. At **15–19** normal years
  or **25–29** rank years, it is `DISPLAY_CAUTION` with a limited-sample
  explanation. At 20/30 or more, no sample-size caution is needed.
- A calculable value is also `DISPLAY_CAUTION` if the underlying variable's
  full-record quality audit shows baseline coverage below 80%, a historical
  gap over 365 days, recent-ten-year coverage below 90%, a recent gap over
  30 days, or any negative precipitation or maximum-below-minimum day.
  These station-level warnings
  do **not** erase complete, valid comparison windows.
- Negative precipitation totals, percentiles outside 0–100, and mean
  temperatures outside −100 to 150 °F are `HIDE_INVALID`. These deliberately
  broad bounds catch impossible outputs without trimming plausible extremes.

`DISPLAY` and `DISPLAY_CAUTION` need no manual approval. Cautions appear
as a dashed outline on local map labels, a compact count in hover tooltips,
and full explanatory text in click popups.
The raw computed values remain in the audit file even when a display value
is hidden. Source-ID transitions and historical flags remain visible in
the quality-context file, but are not automatic blockers: they are common in these
records and do not by themselves show that a complete comparison is wrong.

Optional station-specific exceptions can be entered, if evidence warrants,
one row per station and variable family in
`config/acis-station-publication-reviews.csv`:

```csv
uid,variable,decision,note
1273,pcpn,CAVEAT,Reviewed source history; explain the applicable caveat here
```

Allowed decisions are `APPROVE`, `CAVEAT`, and `EXCLUDE`. `APPROVE` does not
erase automatic cautions. `CAVEAT` adds a caution; `EXCLUDE` hides otherwise
calculable values. A note is required for `CAVEAT` or `EXCLUDE`. The sample
row above is illustrative **only**; it is not a recommendation for that
station. An empty config works automatically. Rerun the script after editing.

The product table includes both its page date and the separate quality-audit
date. Refresh the detailed audit periodically; its age is reported but does
not by itself make all station values suspect. The
15/25 lower floors expand coverage while marking the smaller comparison
samples explicitly. They are a project policy, not a claim that every
station history is homogeneous.

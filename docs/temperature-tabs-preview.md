# Temperature tabs: local presentation review

## Complete grouping pilot

The combined preview now includes these additional pages, all under Current Maps:

| Page | Tabs | Selector |
| --- | --- | --- |
| Daily temperature ranks | Maximum / Mean / Minimum | None |
| Rolling mean temperature ranks | None | 7 / 30 / 90 days |
| Freeze timing and season length | First freeze / Last freeze / Freeze-free season | Date or Length / Departure |
| Dry-spell conditions | Current / Longest in 180 days | Length / Percentile rank |
| Wet-day characteristics | Count / Intensity / Very-wet-day contribution | Measured value (with specific units) / Percentile rank |
| Snow conditions | SWE / Departure / Percent of median / Seven-day change | Selected map / All maps |

All earlier temperature and precipitation pages remain in the same preview.
There are 42 map views. The laptop currently supplies 41 images; seven-day snow
change is absent and has an explicit unavailable notice in both its tab and the
All maps grid. Do not substitute a historical date to fill that gap. The pilot
will use the current snow-change image automatically when it exists locally.

Freeze labels distinguish Date from Length, and note the different seasonal
definitions. Wet-day measured-value labels change with the metric, retaining
the Percentile rank selection across tabs. There are no unsupported temperature
period/variable combinations: daily variable ranks and rolling mean ranks are
separate destinations. Each selected panel carries its own description and
image link. Snow's All maps view retains the selected single-map tab when you
switch back. URL queries preserve the selected tab, display and layout.

Run `source("scripts/preview-current-map-groups.R")` in RStudio to rebuild,
validate and open the isolated preview. Use
`node tests/current-map-group-controls.cjs` after building to test its 26 added
views against the generated combinations. The existing temperature and
precipitation controller tests cover the other sixteen. Production pages,
navigation and map calculations are unchanged by this pilot.

## Earlier preview steps

November 8 extension: this same isolated preview now includes precipitation
totals (1/7/30/90 days) and percentile ranks (7/30/90 days), as two sidebar
destinations with period selectors. There is no daily percentile option because
that product does not exist in this group. The selected panel includes its own
map, interpretation and full-resolution link; the URL preserves the period.
That earlier version contained sixteen maps; the complete pilot above now
also includes freeze, snow and the remaining agreed groupings.

Use `source("scripts/preview-current-map-groups.R")` to rebuild and open the
combined preview. The original temperature preview command remains compatible.

Run from the project root in the laptop RStudio console:

```r
source("scripts/preview-temperature-tabs.R")
```

The script copies nine existing temperature and seven precipitation PNGs and catalog descriptions into
`data/diagnostics/temperature-tabs-preview/`, renders an isolated Quarto site,
checks all sixteen rendered maps and image links, and opens its index in an
interactive R session. No downloads, map calculations, S3 sync or changes to
the real site's sidebar/product pages occur.

The pilot sidebar has **Current Maps → Temperature → Current values** and
**Departures**. Both use Maximum / Mean / Minimum tabs. Departures has a shared
Daily / 30-day mean selector that keeps its selection when switching tabs.
Each visible map has its own catalog description and full-resolution link.
An expandable **Original individual pages** section allows comparison with the
existing presentation. These comparison pages are local copies.

Selecting a variable/period updates the URL query so the view can be bookmarked
or reloaded. All maps remain visible if JavaScript is unavailable. Keyboard
left/right, Home and End keys switch tabs; the period selector uses normal
browser keyboard behavior.

To reopen an already rendered preview:

```r
browseURL(normalizePath("data/diagnostics/temperature-tabs-preview/_site/index.html"))
```

For review, try all three tabs on Current values, then switch the Departures
period to 30-day mean and confirm it stays selected across tabs. Check the
description and full-resolution image match each combination. Compare the
individual pages before deciding whether to adopt the grouped layout.

The map check report is `data/diagnostics/temperature-tabs-preview/validation.csv`.
The JavaScript controller has offline tests (`node tests/temperature-tabs-controls.cjs`)
covering all nine views, retained periods, keyboard controls, saved URLs and
invalid query defaults. No operational navigation change is included yet.

Precipitation control tests: `node tests/precipitation-period-controls.cjs`.
Review the Precipitation sidebar entries and confirm that changing the period
switches the map, description and full-resolution link together. Original
individual precipitation pages are included in the comparison section too.

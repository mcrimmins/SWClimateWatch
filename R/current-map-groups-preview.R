# Additional local grouping experiments; explicit combinations only.
current_preview_groups <- function() {
  group <- function(title, section, rows, all_maps = FALSE) list(title = title, section = section, rows = rows, all_maps = all_maps)
  row <- function(tab, label, variant, option, product) data.frame(tab = tab, label = label,
    variant = variant, option = option, product = product, stringsAsFactors = FALSE)
  list(
    "temperature-daily-ranks" = group("Daily temperature percentile ranks", "Temperature", do.call(rbind,
      lapply(c(maxt = "Maximum", tmean = "Mean", mint = "Minimum"), function(label) {
        variable <- names(c(maxt = "Maximum", tmean = "Mean", mint = "Minimum"))[match(label, c("Maximum", "Mean", "Minimum"))]
        row(variable, label, "rank", "Percentile rank", paste0(variable, "_percentile_daily"))
      }))),
    "temperature-rolling-ranks" = group("Rolling mean temperature ranks", "Temperature", rbind(
      row("mean", "Mean temperature", "7", "7 days", "tmean_percentile_07day"),
      row("mean", "Mean temperature", "30", "30 days", "tmean_percentile_30day"),
      row("mean", "Mean temperature", "90", "90 days", "tmean_percentile_90day"))),
    "freeze-monitoring" = group("Freeze timing and season length", "Temperature", rbind(
      row("first", "First freeze", "observed", "Date", "mint_first_freeze_date"),
      row("first", "First freeze", "departure", "Departure", "mint_first_freeze_departure"),
      row("last", "Last freeze", "observed", "Date", "mint_last_freeze_date"),
      row("last", "Last freeze", "departure", "Departure", "mint_last_freeze_departure"),
      row("length", "Freeze-free season", "observed", "Length", "mint_freeze_free_length"),
      row("length", "Freeze-free season", "departure", "Departure", "mint_freeze_free_departure"))),
    "dry-spells" = group("Dry-spell conditions", "Precipitation", rbind(
      row("current", "Current dry spell", "observed", "Length (days)", "pcpn_current_dry_spell_length"),
      row("current", "Current dry spell", "rank", "Percentile rank", "pcpn_current_dry_spell_percentile"),
      row("longest", "Longest in 180 days", "observed", "Length (days)", "pcpn_longest_dry_spell_180day"),
      row("longest", "Longest in 180 days", "rank", "Percentile rank", "pcpn_longest_dry_spell_percentile_180day"))),
    "wet-days" = group("Wet-day characteristics", "Precipitation", rbind(
      row("count", "Wet-day count", "observed", "Count (days)", "pcpn_wet_day_count_90day"),
      row("count", "Wet-day count", "rank", "Percentile rank", "pcpn_wet_day_count_percentile_90day"),
      row("intensity", "Wet-day intensity", "observed", "Intensity (inches per wet day)", "pcpn_wet_day_intensity_90day"),
      row("intensity", "Wet-day intensity", "rank", "Percentile rank", "pcpn_wet_day_intensity_percentile_90day"),
      row("contribution", "Very-wet-day contribution", "observed", "Contribution (%)", "pcpn_very_wet_contribution_90day"),
      row("contribution", "Very-wet-day contribution", "rank", "Percentile rank", "pcpn_very_wet_contribution_percentile_90day"))),
    "snow-conditions" = group("Snow conditions", "Snow", rbind(
      row("swe", "SWE", "map", "SWE", "snow_swe"),
      row("departure", "Departure", "map", "Departure", "snow_departure"),
      row("percent", "Percent of median", "map", "Percent of median", "snow_percent"),
      row("change", "7-day change", "map", "7-day change", "snow_change")), all_maps = TRUE)
  )
}

current_preview_snow_products <- function() list(
  snow_swe = list(group = "Snow", label = "Snow water equivalent", image = "snodas/current/swe-observed.png",
    description = "Modeled snowpack water in inches, not daily snowfall. Pale areas may be snow-free; missing cells remain uncolored. Dates are printed on each map."),
  snow_departure = list(group = "Snow", label = "SWE departure", image = "snodas/current/swe-departure.png",
    description = "SWE minus the centered-five-day WY2005–WY2025 date-specific median, in inches. Positive values mean more snow water than the reference median."),
  snow_percent = list(group = "Snow", label = "SWE percent of median", image = "snodas/current/swe-percent-median.png",
    description = "SWE divided by the date-specific median, times 100. Ratios require a median of at least 1 inch and 18 reference years. Gray indicates low typical SWE; this is not a percentile."),
  snow_change = list(group = "Snow", label = "Seven-day SWE change", image = "snodas/current/swe-change-7day.png",
    description = "Net modeled snowpack-water gain or loss over exactly seven days, in inches. This is not snowfall, and losses are not a measure of melt alone.")
)

current_group_preview_page <- function(key, group, products, available) {
  rows <- group$rows; tabs <- rows[!duplicated(rows$tab), ]
  lines <- c('---', paste0('title: "', group$title, '"'), 'page-layout: full', 'toc: false', '---', '', '```{=html}',
    sprintf('<div class="current-group-preview" data-group="%s">', key),
    '<p class="temperature-preview-note">Local layout review · Existing maps; dates are printed on each map.</p>')
  if (!is.null(group$intro)) lines <- c(lines, paste0("<p>", temperature_preview_escape(group$intro), "</p>"))
  if (key == "wet-days") lines <- c(lines, '<p>All three measures describe the latest 90 days. Wet days have at least 0.04 inch of precipitation.</p>')
  if (key == "freeze-monitoring") lines <- c(lines, '<p>First/last freeze maps use August–July cold seasons; freeze-free length uses the displayed calendar year. Check each map’s year before comparing.</p>')
  if (group$all_maps) lines <- c(lines, '<div class="temperature-period-control"><label for="group-layout">View</label><select id="group-layout"><option value="single">Selected map</option><option value="all">All maps</option></select></div>')
  lines <- c(lines, sprintf('<div class="temperature-variable-tabs" role="tablist" aria-label="%s">', group$title))
  for (i in seq_len(nrow(tabs))) lines <- c(lines, sprintf('<button type="button" id="group-tab-%s" role="tab" data-tab="%s" aria-controls="group-maps">%s</button>', tabs$tab[i], tabs$tab[i], tabs$label[i]))
  lines <- c(lines, '</div>', sprintf('<div class="temperature-period-control group-variant-control"><label for="group-variant">%s</label><select id="group-variant"></select></div>',
      if (key == "temperature-rolling-ranks") "Time period" else "Display"),
    '<div id="group-maps" role="tabpanel" aria-live="polite">')
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]; p <- products[[r$product]]; src <- paste0("maps/", basename(p$image))
    lines <- c(lines, sprintf('<article class="group-map" data-product="%s" data-tab="%s" data-variant="%s" data-option="%s"><h2 class="group-map-heading">%s</h2>',
      r$product, r$tab, r$variant, temperature_preview_escape(r$option), temperature_preview_escape(p$label)))
    if (!is.null(group$tab_notes[[r$tab]])) lines <- c(lines, paste0('<p class="group-map-caution">', temperature_preview_escape(group$tab_notes[[r$tab]]), '</p>'))
    if (available[[r$product]]) lines <- c(lines, sprintf('<a href="%s" target="_blank" rel="noopener"><img src="%s" alt="%s" loading="lazy"></a>', src, src, temperature_preview_escape(p$label))) else
      lines <- c(lines, paste0('<p class="group-unavailable" role="status">',
        temperature_preview_escape(if (!is.null(group$unavailable_notes[[r$product]])) group$unavailable_notes[[r$product]] else
          "This map is not available in the laptop’s current cached set. No map from a different date has been substituted."), '</p>'))
    lines <- c(lines, paste0('<p>', temperature_preview_escape(p$description), '</p>'))
    if (available[[r$product]]) lines <- c(lines, sprintf('<p><a href="%s" target="_blank" rel="noopener">Open full-resolution PNG</a> · <a href="individual/%s.html">Original individual map page</a></p>', src, r$product))
    lines <- c(lines, '</article>')
  }
  c(lines, '</div></div><script src="current-map-groups.js"></script>', '```')
}

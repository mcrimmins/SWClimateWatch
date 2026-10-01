# Research-only automatic screening for the unpublished station explorer.
# Source acis-station-explorer-prototype.R before calling these functions.

acis_station_publication_reviews <- function(reviews, uids) {
  required <- c("uid", "variable", "decision", "note")
  if (is.null(reviews)) reviews <- data.frame(
    uid = integer(), variable = character(), decision = character(),
    note = character())
  if (!all(required %in% names(reviews)))
    stop("Station review decisions lack: ",
         paste(setdiff(required, names(reviews)), collapse = ", "))
  reviews <- reviews[, required, drop = FALSE]
  reviews$uid <- as.integer(reviews$uid)
  reviews$variable <- trimws(as.character(reviews$variable))
  reviews$decision <- toupper(trimws(as.character(reviews$decision)))
  reviews$note <- trimws(as.character(reviews$note))
  reviews$note[is.na(reviews$note)] <- ""
  if (anyNA(reviews$uid) || any(!reviews$uid %in% uids) ||
      any(!reviews$variable %in% c("pcpn", "tmean")) ||
      any(!reviews$decision %in% c("APPROVE", "CAVEAT", "EXCLUDE")) ||
      any(duplicated(reviews[c("uid", "variable")])) ||
      any(reviews$decision %in% c("CAVEAT", "EXCLUDE") & !nzchar(reviews$note)))
    stop("Invalid station review decision: check uid, variable, decision, unique keys and required notes.")
  reviews
}

audit_acis_station_publication <- function(rows, quality, checks, reviews = NULL) {
  needed <- list(
    explorer = c("uid", "sid", "name", "state", "role", "as_of", "period",
                 "cache_as_of", "longitude", "latitude",
                 "pcpn_normal_years", "tmean_normal_years",
                 "pcpn_reference_years", "tmean_reference_years"),
    quality = c("uid", "variable", "as_of", "baseline_coverage",
                "recent10_coverage", "latest_lag_days",
                "baseline_longest_gap_days", "recent10_longest_gap_days",
                "special_flag_days", "accumulated_days",
                "source_id_transitions", "distinct_source_ids"),
    checks = c("uid", "maxt_below_mint_days", "negative_pcpn_days"))
  inputs <- list(explorer = rows, quality = quality, checks = checks)
  for (name in names(inputs))
    if (!all(needed[[name]] %in% names(inputs[[name]])))
      stop(name, " lacks: ", paste(setdiff(needed[[name]],
                                        names(inputs[[name]])), collapse = ", "))
  if (!nrow(rows) || length(unique(rows$as_of)) != 1L ||
      any(duplicated(rows[c("uid", "period")])) ||
      any(duplicated(quality[c("uid", "variable")])) ||
      any(duplicated(checks["uid"])))
    stop("Station inputs need one page date and unique station-period and audit keys.")
  qkeys <- paste(quality$uid, quality$variable)
  expected <- as.vector(outer(unique(rows$uid), c("maxt", "mint", "pcpn"), paste))
  if (!setequal(quality$uid, rows$uid) || !setequal(checks$uid, rows$uid) ||
      !all(expected %in% qkeys))
    stop("Station and daily-quality identities do not reconcile.")
  reviews <- acis_station_publication_reviews(reviews, unique(rows$uid))
  coverage <- acis_station_explorer_coverage(rows)$detail
  if (nrow(coverage) != nrow(rows) * length(acis_station_explorer_map_metrics))
    stop("Product coverage row count does not reconcile.")
  coverage$variable <- sub("_.*", "", coverage$metric)
  coverage$page_date <- coverage$as_of
  coverage$cache_as_of <- rows$cache_as_of[match(
    paste(coverage$uid, coverage$period), paste(rows$uid, rows$period))]
  review_ix <- match(paste(coverage$uid, coverage$variable),
                     paste(reviews$uid, reviews$variable))
  coverage$manual_decision <- reviews$decision[review_ix]
  coverage$review_note <- reviews$note[review_ix]

  station_rows <- rows[!duplicated(rows$uid),
                       c("uid", "sid", "name", "state", "role", "longitude", "latitude")]
  queue <- do.call(rbind, lapply(c("pcpn", "tmean"), function(variable) {
    qvars <- if (variable == "pcpn") "pcpn" else c("maxt", "mint")
    out <- station_rows
    out$variable <- variable
    out$mapped <- out$role == "fixed" & is.finite(out$longitude) &
      is.finite(out$latitude)
    out$page_date <- as.character(rows$as_of[[1L]])
    out$quality_audit_dates <- NA_character_
    out$quality_audit_age_days <- NA_integer_
    for (field in c("baseline_coverage_min", "recent10_coverage_min",
                    "latest_lag_days_max", "baseline_longest_gap_days_max",
                    "recent10_longest_gap_days_max", "source_id_transitions_total",
                    "distinct_source_ids_max", "special_flag_days_total",
                    "accumulated_days_total", "consistency_issue_days",
                    "available_products", "total_products"))
      out[[field]] <- NA_real_
    out$manual_decision <- NA_character_
    out$review_note <- NA_character_
    for (j in seq_len(nrow(out))) {
      q <- quality[quality$uid == out$uid[[j]] &
                     quality$variable %in% qvars, , drop = FALSE]
      dates <- as.Date(q$as_of)
      out$quality_audit_dates[[j]] <- paste(sort(unique(as.character(dates))),
                                            collapse = ";")
      out$quality_audit_age_days[[j]] <- max(as.integer(
        as.Date(out$page_date[[j]]) - dates))
      out$baseline_coverage_min[[j]] <- min(q$baseline_coverage)
      out$recent10_coverage_min[[j]] <- min(q$recent10_coverage)
      out$latest_lag_days_max[[j]] <- max(q$latest_lag_days)
      out$baseline_longest_gap_days_max[[j]] <- max(q$baseline_longest_gap_days)
      out$recent10_longest_gap_days_max[[j]] <- max(q$recent10_longest_gap_days)
      out$source_id_transitions_total[[j]] <- sum(q$source_id_transitions)
      out$distinct_source_ids_max[[j]] <- max(q$distinct_source_ids)
      out$special_flag_days_total[[j]] <- sum(q$special_flag_days)
      out$accumulated_days_total[[j]] <- sum(q$accumulated_days)
      check <- checks[checks$uid == out$uid[[j]], , drop = FALSE]
      out$consistency_issue_days[[j]] <- if (variable == "pcpn")
        check$negative_pcpn_days[[1L]] else check$maxt_below_mint_days[[1L]]
      p <- coverage[coverage$uid == out$uid[[j]] &
                      coverage$variable == variable, , drop = FALSE]
      out$available_products[[j]] <- sum(p$reason_code %in%
        c("AVAILABLE", "PROVISIONAL_TOTAL", "NEAR_COMPLETE_TEMPERATURE",
          "PARTIAL_TEMPERATURE"))
      out$total_products[[j]] <- nrow(p)
      review <- reviews[reviews$uid == out$uid[[j]] &
                          reviews$variable == variable, , drop = FALSE]
      if (nrow(review)) {
        out$manual_decision[[j]] <- review$decision[[1L]]
        out$review_note[[j]] <- review$note[[1L]]
      }
    }
    out
  }))
  rownames(queue) <- NULL
  products <- coverage[, c("uid", "sid", "name", "state", "role", "mapped",
                           "page_date", "cache_as_of", "period", "metric", "variable",
                           "value", "current_status", "missing_days", "flagged_days",
                           "normal_years", "reference_years", "reason_code", "reason",
                           "manual_decision", "review_note")]
  qix <- match(paste(products$uid, products$variable),
               paste(queue$uid, queue$variable))
  products$quality_audit_dates <- queue$quality_audit_dates[qix]
  products$quality_audit_age_days <- queue$quality_audit_age_days[qix]
  caution <- function(condition, code) if (isTRUE(condition)) code else character()
  products$caution_codes <- vapply(seq_len(nrow(products)), function(i) {
    q <- queue[qix[[i]], , drop = FALSE]
    metric <- products$metric[[i]]
    codes <- c(
      caution(products$current_status[[i]] == "PROVISIONAL" &&
                metric == "pcpn_value", "PROVISIONAL_PRECIP"),
      caution(products$current_status[[i]] == "PARTIAL" &&
                startsWith(metric, "tmean_"), "PARTIAL_TEMPERATURE"),
      caution(grepl("_anomaly$", metric) &&
                products$normal_years[[i]] < acis_station_standard_normal_years,
              "LIMITED_NORMAL_SAMPLE"),
      caution(grepl("_percentile$", metric) &&
                products$reference_years[[i]] < acis_station_standard_rank_years,
              "LIMITED_RANK_SAMPLE"),
      caution(q$baseline_coverage_min[[1L]] < 0.8, "LOW_BASELINE_COVERAGE"),
      caution(q$baseline_longest_gap_days_max[[1L]] > 365,
              "LONG_BASELINE_GAP"),
      caution(q$recent10_coverage_min[[1L]] < 0.9, "LOW_RECENT_COVERAGE"),
      caution(q$recent10_longest_gap_days_max[[1L]] > 30,
              "LONG_RECENT_GAP"),
      caution(q$consistency_issue_days[[1L]] > 0, "CONSISTENCY_ISSUE"),
      caution(anyNA(q[c("quality_audit_age_days", "baseline_coverage_min",
                        "recent10_coverage_min", "consistency_issue_days")]),
              "QUALITY_AUDIT_INCOMPLETE"),
      caution(identical(products$manual_decision[[i]], "CAVEAT"),
              "MANUAL_CAVEAT"))
    paste(codes, collapse = ";")
  }, character(1))
  invalid <- (products$metric == "pcpn_value" & is.finite(products$value) &
                products$value < 0) |
    (grepl("_percentile$", products$metric) & is.finite(products$value) &
       (products$value < 0 | products$value > 100)) |
    (products$metric == "tmean_value" & is.finite(products$value) &
       (products$value < -100 | products$value > 150))
  products$publication_status <- ifelse(
    !products$reason_code %in%
      c("AVAILABLE", "PROVISIONAL_TOTAL", "NEAR_COMPLETE_TEMPERATURE",
        "PARTIAL_TEMPERATURE"),
    "HIDE_UNAVAILABLE",
    ifelse(invalid, "HIDE_INVALID",
           ifelse(!is.na(products$manual_decision) &
                    products$manual_decision == "EXCLUDE", "HIDE_EXCLUDED",
                  ifelse(nzchar(products$caution_codes), "DISPLAY_CAUTION",
                         "DISPLAY"))))
  products$display_value <- ifelse(
    products$publication_status %in% c("DISPLAY", "DISPLAY_CAUTION"),
    products$value, NA_real_)
  products <- products[order(match(products$period, acis_station_explorer_periods),
                             match(products$metric, acis_station_explorer_map_metrics),
                             products$state, products$name), ]
  rownames(products) <- NULL
  summary <- as.data.frame(table(
    audience = ifelse(products$mapped, "mapped_fixed", "table_only"),
    period = factor(products$period, levels = acis_station_explorer_periods),
    metric = factor(products$metric, levels = acis_station_explorer_map_metrics),
    publication_status = factor(products$publication_status,
      levels = c("DISPLAY", "DISPLAY_CAUTION", "HIDE_UNAVAILABLE",
                 "HIDE_INVALID", "HIDE_EXCLUDED"))), stringsAsFactors = FALSE)
  names(summary)[5L] <- "station_count"
  summary <- summary[summary$station_count > 0, , drop = FALSE]
  rownames(summary) <- NULL
  if (sum(summary$station_count) != nrow(products))
    stop("Publication summary does not reconcile to product rows.")
  sensitivity <- do.call(rbind, lapply(c("pcpn", "tmean"), function(variable)
    do.call(rbind, lapply(c("anomaly", "percentile"), function(kind)
      do.call(rbind, lapply(if (kind == "anomaly") c(15L, 20L, 25L)
                             else c(25L, 30L, 40L), function(n) {
        years <- rows[[paste0(variable, if (kind == "anomaly")
          "_normal_years" else "_reference_years")]]
        count <- !is.na(years) & years >= n
        current_ok <- !is.na(rows[[paste0(variable, "_status")]]) &
          rows[[paste0(variable, "_status")]] %in% if (variable == "tmean")
            c("AVAILABLE", "NEAR_COMPLETE", "PARTIAL") else "AVAILABLE"
        data.frame(period = acis_station_explorer_periods,
                   metric = paste(variable, kind, sep = "_"),
                   comparison = if (kind == "anomaly")
                     "1991-2020 normals" else "prior years",
                   min_years = n,
                   mapped_current_complete = vapply(acis_station_explorer_periods,
                     function(p) sum(rows$period == p & rows$role == "fixed" &
                                       current_ok), integer(1)),
                   mapped_meeting_threshold = vapply(acis_station_explorer_periods,
                     function(p) sum(rows$period == p & rows$role == "fixed" &
                                       current_ok & count), integer(1)))
      }))))))
  rownames(sensitivity) <- NULL
  list(products = products, quality_context = queue, summary = summary,
       threshold_sensitivity = sensitivity)
}

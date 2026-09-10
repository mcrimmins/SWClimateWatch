# Bounded orchestration for local PRISM archive development.

summarize_prism_bootstrap <- function(
    plan = plan_prism_download("bootstrap"),
    max_requests = swc_prism$max_requests_per_run) {
  prepared <- prepare_prism_request_queue(plan, max_requests = max_requests)
  data.frame(
    total_requests = unname(prepared$summary[["total"]]),
    downloaded_files = unname(prepared$summary[["already_complete"]]),
    remaining_requests = unname(prepared$summary[["eligible"]]),
    scheduled_this_run = unname(prepared$summary[["will_run"]]),
    deferred = unname(prepared$summary[["deferred"]]),
    stringsAsFactors = FALSE
  )
}

run_prism_bootstrap_batch <- function(
    max_requests = 25L,
    variables = swc_prism$variables,
    start = swc_prism$archive_start,
    end = swc_prism$archive_end,
    delay_seconds = swc_prism$request_delay_seconds,
    jitter_seconds = swc_prism$request_jitter_seconds,
    quiet = FALSE) {
  plan <- plan_prism_download(
    mode = "bootstrap",
    variables = variables,
    start = start,
    end = end
  )
  before <- summarize_prism_bootstrap(plan, max_requests = max_requests)
  if (!quiet) {
    message(
      "Bootstrap status before run: ", before$downloaded_files, "/",
      before$total_requests, " downloaded; ", before$scheduled_this_run,
      " scheduled."
    )
  }

  downloaded <- download_prism_plan(
    plan,
    max_requests = max_requests,
    delay_seconds = delay_seconds,
    jitter_seconds = jitter_seconds,
    quiet = quiet
  )
  processing_plan <- plan_prism_daily_processing(variables = variables)
  processed <- process_prism_daily_plan(processing_plan, quiet = quiet)

  refreshed_plan <- plan_prism_download(
    mode = "bootstrap",
    variables = variables,
    start = start,
    end = end
  )
  after <- summarize_prism_bootstrap(refreshed_plan, max_requests = max_requests)
  current_processing <- plan_prism_daily_processing(variables = variables)
  processing_current <- if (nrow(current_processing) == 0L) {
    0L
  } else {
    sum(!current_processing$refresh)
  }
  processing_pending <- if (nrow(current_processing) == 0L) {
    0L
  } else {
    sum(current_processing$refresh)
  }

  status <- data.frame(
    downloaded_this_run = nrow(downloaded),
    processed_this_run = nrow(processed),
    downloaded_total = after$downloaded_files,
    download_remaining = after$remaining_requests,
    processed_current = processing_current,
    processing_pending = processing_pending,
    stringsAsFactors = FALSE
  )
  if (!quiet) {
    message(
      "Bootstrap batch complete: ", status$downloaded_this_run, " downloaded; ",
      status$processed_this_run, " processed; ", status$download_remaining,
      " requests remain."
    )
  }

  invisible(list(
    downloaded = downloaded,
    processed = processed,
    status = status
  ))
}

#include <Rcpp.h>
#include <cmath>

// [[Rcpp::export]]
Rcpp::NumericVector swc_longest_dry_windows_cpp(
    Rcpp::NumericVector values,
    Rcpp::IntegerVector window_starts,
    int duration_days,
    double wet_cutoff) {
  if (duration_days < 1) Rcpp::stop("Invalid longest-dry-spell duration.");
  Rcpp::NumericVector answer(window_starts.size());
  for (R_xlen_t j = 0; j < window_starts.size(); ++j) {
    const int start = window_starts[j] - 1;
    if (window_starts[j] == NA_INTEGER || start < 0 ||
        static_cast<R_xlen_t>(start) + duration_days > values.size()) {
      Rcpp::stop("Longest-dry-spell window lies outside its source values.");
    }
    int longest = 0;
    int current = 0;
    bool missing = false;
    for (int i = start; i < start + duration_days; ++i) {
      const double value = values[i];
      if (Rcpp::NumericVector::is_na(value) || std::isnan(value)) {
        missing = true;
        break;
      }
      if (value >= wet_cutoff) {
        current = 0;
      } else {
        ++current;
        if (current > longest) longest = current;
      }
    }
    answer[j] = missing ? NA_REAL : static_cast<double>(longest);
  }
  return answer;
}

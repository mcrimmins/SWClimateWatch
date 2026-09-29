# SNODAS remaining work

## Current-season readiness and remaining operations

The October-May downloader, regional SWE/depth processing, and
WY2005-WY2025 daily reference are ready for manual use starting October 1,
2026 (WY2027). `source("scripts/update-snodas.R")` now also selects the
latest *verified processed* date within WY2027, builds observed SWE and
departure from the centered-five-day median, applies the map-quality gate,
and stages a dated [Current Snow](../site/pages/current-snow.qmd) page with
two PNGs only on `PASS`. Missing or screened cells remain distinct from
zero snow. If no current archive has posted yet, the page shows a waiting
state; `REVIEW` and `FAIL` do not silently replace the prior approved map.
The historical peak-SWE/snow-covered-day archive is a separate workflow.

The standalone snow script is **manual local-site readiness**: it does not
render Quarto or deploy to S3. A separate
[`daily-update-and-publish.R`](../scripts/daily-update-and-publish.R) entry
point now runs PRISM and SNODAS together, renders, validates, and syncs changed
site content when manually started. Neither entry point is scheduled. Before
enabling unattended operation, test one real WY2027 posting end-to-end and
confirm map date and quality. Also add a deliberate policy for detecting later NSIDC revisions
to already processed dates; the current directory inventory cannot reveal
changed archive contents. The first October run may find no posted data.

## Later: seasonal snow anomalies

Add an end-of-season anomaly companion to the Historic Years snow cards. The
first candidate is **seasonal peak-SWE departure** (inches): at each grid cell,
subtract the median of the WY2005-WY2025 *seasonal peak SWE values* from that
year's October-May peak SWE. Compute the median from one QC-screened peak per
water year; do not use the daily calendar-date SWE median for this product.

Before publishing, decide and document minimum valid-year support, treatment
of years with missing days, and how to display the widespread zero-median
lowlands. Test the distribution and legend on both low- and high-snow years,
and reuse the seasonal peak-QC rules. Consider snow-covered-day departure as
a separate persistence measure. A seven-day change in current SWE is another
distinct monitoring product, not a seasonal anomaly.

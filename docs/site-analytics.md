# Google Analytics

Configured November 4, 2026 for GA4 measurement ID `G-XS7RFBPW01`.
The tag is prepared in source; production collection begins after this release
is rendered and promoted. No climate-data download or R calculation is added.

The Quarto header include and standalone Station Conditions/Daily Explorer
templates bootstrap `site/assets/site-analytics.js`. Collection requires the
exact host `cales.arizona.edu` and the `/climate/watch/` path (or `/climate/watch`).
Local previews, other hostnames and `/climate/watch-staging/` load neither the
Google library nor the production analytics asset. Embedded tools defer to
their outer page, preventing duplicate visits; full-screen tools are tracked
as their own top-level pages. Query strings and fragments are omitted from
the explicitly configured page location. Google signals and ad personalization
signals are disabled. No custom station/date interaction events are added yet.

Tests run without contacting Google:

```sh
node tests/test-site-analytics.cjs
```

On staging, verify the bootstrap and asset are present in rendered output and
that no Google Analytics collection requests occur in the browser. After
production promotion, open a page and check its visit in GA4 Realtime or Google
Tag Assistant. Allow for browser blocking/consent settings when interpreting
missing visits; a local unit test cannot verify collection in the GA4 account.
Manage access, retention and applicable consent settings in the Analytics
property. Custom events and developer-traffic exclusions remain follow-up work.

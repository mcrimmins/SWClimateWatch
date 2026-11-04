/* Basic GA4 page views. The host/path/frame guard also applies to direct loads. */
(() => {
  "use strict";
  if (window.location.hostname !== "cales.arizona.edu" ||
      !/^\/climate\/watch(?:\/|$)/.test(window.location.pathname) ||
      window.self !== window.top || window.__swcAnalyticsInitialized) return;
  window.__swcAnalyticsInitialized = true;
  const measurementId = "G-XS7RFBPW01";
  window.dataLayer = window.dataLayer || [];
  window.gtag = window.gtag || function() { window.dataLayer.push(arguments); };
  window.gtag("js", new Date());
  window.gtag("config", measurementId, {
    page_location: window.location.origin + window.location.pathname,
    allow_google_signals: false,
    allow_ad_personalization_signals: false
  });
  const script = document.createElement("script");
  script.async = true;
  script.src = "https://www.googletagmanager.com/gtag/js?id=" + measurementId;
  document.head.appendChild(script);
})();

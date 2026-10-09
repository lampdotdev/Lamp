import type { PostHog } from "posthog-js";

// PostHog for the site: page views, clicks, the Download buttons and the first-idea section's steps. No
// cookies or local storage (persistence: "memory"), so a visit is counted from page load to leaving and
// there's nothing to ask consent for. Nothing typed is sent: autocapture never reads form fields, it skips the
// first-idea section (`ph-no-capture`), whose buttons repeat a model's words about what the visitor wrote, and
// that section's own events carry only what /api/idea-event already counts.
// Without PUBLIC_POSTHOG_KEY (local dev, preview builds) nothing loads and `track` does nothing. With it, the
// library loads after the page, so it never holds up the first paint.
const key = import.meta.env.PUBLIC_POSTHOG_KEY;
let client: Promise<PostHog> | null = null;

export function startAnalytics() {
  if (!key || client) return client;
  client = import("posthog-js").then(({ default: posthog }) => {
    posthog.init(key, {
      api_host: import.meta.env.PUBLIC_POSTHOG_HOST || "https://us.i.posthog.com",
      persistence: "memory",
      person_profiles: "identified_only",
      capture_pageview: true,
      capture_pageleave: true,
      autocapture: true,
      disable_session_recording: true,
      disable_surveys: true,
    });
    return posthog;
  });
  return client;
}

export function track(event: string, properties: Record<string, string | number | boolean> = {}) {
  startAnalytics()?.then((posthog) => posthog.capture(event, properties)).catch(() => {});
}

# Browser connector experiment

A throwaway Chrome page handoff, disabled unless Lamp Dev starts with
`LAMP_BROWSER_PROTOTYPE=1`. It is not a release feature. No provider account,
application registration, API key or pairing code is involved.

The path is Chrome's action popup → native messaging helper → Lamp Dev's existing
loopback gateway → the requesting generated app. `activeTab` grants access only
following a browser gesture. The popup names the destination and asks before
reading rendered text. There are no host permissions, cookie permissions,
content-script listeners, external-message listeners, page actions or cloud calls.

The two fixture apps are scaffolded by the real `Template.scaffold`, keep the
unmodified Lamp-owned support/build/package files, and save received pages with
`LampStore`. Their custom view contains the prototype client. No model is needed
to author these predetermined fixtures; this does not exercise the coding-agent
conversation or constitute a general connector supplied to every generated app.

## Build and try

Use a private clean lampvm clone as described in the repository's workflow rules.
Keep the VM held through rebuilds and destroy only that clone after collecting proof.
Never use real browser sign-ins or copy host application data into it.

1. Run `experiments/browser-connector/build.sh` on the build machine. It uses ad-hoc
   signing, bundles the native helper, and produces `build/Lamp Dev.app`.
2. Install that app in the guest. Copy this experiment directory to
   `/tmp/browser-connector` in the guest. Install ordinary Google Chrome there.
3. Start the fixture website in the guest:
   `python3 /tmp/browser-connector/site.py`.
4. Start the guest's Lamp Dev executable with `LAMP_BROWSER_PROTOTYPE=1` and
   `LAMP_BROWSER_FIXTURES=/tmp/browser-connector`. This writes the per-user native
   host manifest and creates Page Shelf and Other Shelf under Lamp Dev's Apps
   folder. It reuses those folders on later starts. The helper/configuration live
   in `Edition.supportFolder/BrowserPrototype`, outside the signed app bundle.
5. Build each generated project with its own `build.sh` and install its app in the
   guest. With Command Line Tools lacking SwiftUI's latest compiler macro, set
   `SDKROOT` to an installed compatible SDK, as Lamp's build environment does.
6. In Chrome, open `chrome://extensions`, enable **Developer mode**, click
   **Load unpacked**, and select `/tmp/browser-connector/extension`.
7. Visit `http://127.0.0.1:8765` and choose **Sign in to demo account**. The server
   creates a fictional HttpOnly cookie session; signed-out requests cannot see
   the private orders. No cookie leaves Chrome through the extension.
8. Open Page Shelf and click **Get current page**. Return to Chrome, open the
   extension from the Extensions menu (or pin it), and click **Share with Page
   Shelf**. The page title, URL, rendered text and capture time appear in the app.
   Start both apps' requests to try destination selection and separation.

Requests expire after two minutes. Reopening the popup makes a fresh native host
session. Closing a popup before approving sends nothing; Cancel ends its app
request. Browser restart needs no new registration. Restarting Lamp intentionally
loses pending requests; the app can ask again. One-time results are removed when
read; the destination keeps its own saved copy.

## Boundaries and workarounds

- **Developer mode / unpacked loading is a development workaround.** It is not a
  measured Chrome Web Store installation. The fixed manifest public key stabilizes
  the unpacked extension ID; it is not a user-entered credential or production
  extension identity. There is no private signing key in this repository.
- **Native messaging is a supported Chrome mechanism.** Per-user registration is
  automatic here, with no administrator prompt. Shipping needs a stable published
  extension ID, signed helper packaging, installer/update repair, and store review.
- The bridge authenticates requests and replies with an installation secret and
  binds each approval to app/request, exact origin and URL, native connection,
  tab, document, challenge and expiry. Results and approvals are one-use. Native
  requests reject browser Origin headers, nonlocal Host headers and the phone
  listener. An impersonating local HTTP server cannot return an accepted response
  without the secret.
- **This retains Lamp's existing bearer-token trust boundary.** Unsandboxed apps
  running as the same macOS user can read tokens or bridge files. This is not
  protection from a malicious local app. Production needs a separate decision
  about process identity and runtime isolation, not merely more popup checks.
- A destination app can retransmit data. The local-only consent copy is accurate
  for these two fixture apps only; a general API needs trustworthy disclosure and
  enforcement of onward use. Page text remains untrusted content.
- HTTP is accepted only for loopback fixtures; other origins must use HTTPS.
  The fixture app's requested origin is deliberately fixed. This is not a
  catalog of service connectors, account discovery or background synchronization.
- Text extraction excludes form values, editable areas, hidden nodes and frames,
  capped at 24,000 UTF-16 units / 100,000 UTF-8 bytes. It is not a DOM sanitizer or
  complete service export. Canvas, shadow DOM, unloaded rows and frame contents
  need separate evaluation. Same-document changes can occur while a popup is open;
  consent is to capture the current document when clicked, not a frozen preview.
- No Safari, Arc, Brave, store distribution, organization policy, real service
  login, AI generation, phone or scheduled/background access is implied.

The main/article-first extraction approach was informed by
[Local's connector](https://github.com/RooCodeInc/local/blob/a64391f3b27535adb91aa12c60955e5514319fdc/browser-extension/background.js).
Transport and permission references: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging),
[activeTab](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab),
[unpacked development installation](https://developer.chrome.com/docs/extensions/get-started/tutorial/hello-world).

Put screenshots, recordings, live logs and review findings in an external proof
folder. Do not commit browser profiles, captures, generated apps, build output or
installation secrets. Remove the two Store hooks, BrowserPrototype.swift and this
folder to discard the experiment.

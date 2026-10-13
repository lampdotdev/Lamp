# Standing browser access experiment

Throwaway Chrome connector, enabled only when Lamp Dev starts with
`LAMP_BROWSER_PROTOTYPE=1`. One extension serves separate generated apps. No
service registration, credential paste or pairing code is involved.

A generated app asks for an exact site. The extension's **Browser access** tab
names that app and site; **Allow this app on this site** requests Chrome's optional
host permission and saves a separate Lamp app grant. This view is a persistent
extension tab so a Chrome permission sheet cannot destroy its pending approval.
Subsequent app requests need no browser gesture or open management view.

## Run in a private VM

Follow the repository's lampvm workflow. Never copy real settings, browser
profiles, sign-ins or signing keys into the guest.

1. Build with `experiments/browser-connector/build.sh` (ad-hoc signed Lamp Dev and
   its native helper). Install `build/Lamp Dev.app` in the guest.
2. Copy this folder to guest `/tmp/browser-connector`; run its `site.py` there.
   Install ordinary Google Chrome in the guest.
3. Start the guest Lamp Dev executable with `LAMP_BROWSER_PROTOTYPE=1` and
   `LAMP_BROWSER_FIXTURES=/tmp/browser-connector`. This registers the per-user
   Chrome native host and scaffolds Page Shelf and Other Shelf through the real
   `Template.scaffold`. Build each project's unchanged `build.sh`, using a
   compatible installed SDK through `SDKROOT` when necessary, and install its
   generated app. Fixture views are predefined; no model conversation is involved.
4. In `chrome://extensions`, enable Developer mode, choose Load unpacked and this
   folder's `extension` directory. Pin the toolbar icon to use the task recorder.
5. Open `http://127.0.0.1:8765` and sign into the fictional demo account. The second
   origin is `http://localhost:8765`, with its own browser session cookie.
6. In an app, choose the site, then **Ask for site access**. Click the extension
   toolbar button and approve. Chrome may ask separately for site permission.
7. Use **Read page**, or enable **Read every 5 seconds** in the fixture app. Switch
   to another browser tab to exercise background reads. `/advance` increments the
   fixture's live revision, which the page updates using its own JavaScript.
8. Open the extension again to see named grants and **Revoke**. Revocation stops
   future reads and discards captured results not yet collected by the app. It
   cannot remove copies already saved in the app.

## Behavior and boundaries

- Chrome gets optional HTTPS host permissions, plus loopback HTTP for the demo.
  `activeTab` supplies the task recorder's site suggestion on a toolbar click;
  there is no `tabs`, cookies or management permission. Chrome host
  permissions are extension-wide and technically permit read/write; the code
  deliberately offers only bounded text capture. Lamp enforces app/site grants.
- Open background tabs are readable without activating them. Exact URL matches
  are required; duplicate matching tabs are refused instead of choosing an account.
- Closed pages fail by default. The approval checkbox **Open a background tab if
  the page is closed** permits `tabs.create({active:false})`, then a capture of
  that document. It creates an ordinary visible tab, not an invisible browser.
  A closed browser cannot execute this extension; a missing session still needs
  normal website sign-in. No promise of permanent authentication is made.
- The MV3 service worker connects through Chrome native messaging. Its native port
  uses Chrome's documented keepalive rule. A one-second polling loop requests
  jobs through the existing Lamp gateway; an alarm can reconnect the worker. The
  frequent polling and fixed fixture URLs are prototype simplifications.
- Native requests and responses are authenticated with an automatically generated
  installation secret. Grants persist with app ID, app instance, exact origin,
  browser-profile identity and a fresh grant ID. Jobs also bind a native session
  and one-use challenge. Every capture rechecks the grant/permission, URL and
  document. Browser permission removal invalidates queued sends synchronously.
- App tokens still inherit Lamp's existing same-user trust boundary: hostile
  unsandboxed native apps can read files and impersonate one another. This is not
  a production runtime isolation design. The local-only consent statement applies
  only to the fixture apps, which do not send their saved text to a cloud service.
- Revoking one app preserves other apps' grants. If no grant in this browser uses
  that origin, the extension removes Chrome's optional permission too. Chrome can
  remember permission previously accepted; reapproval need not repeat its prompt.
  Removing Chrome permission also removes the corresponding Lamp grants. Failure
  to save revocation still blocks it in memory and reports failed persistence;
  removing Chrome site access additionally prevents reads after a relaunch.
- There are no external-message handlers or listeners for website `postMessage`.
  Standing-access commands come from the extension's own pages. The task recorder
  additionally accepts its injected content script's bounded observations and
  Stop/Discard, checking sender origin, frame and recording identity.
  Standing-access text extraction skips field values, editable/hidden content
  and frames, capped at 24,000 UTF-16 units / 100,000 UTF-8 bytes. It is not a
  complete website export; page text is untrusted data.
- `inspect.html` displays live permission state and Chrome's
  `getPermissionWarningsByManifest` results for optional access versus a required
  all-sites manifest. This is diagnostic API output, not a store install dialog.

**Development workarounds:** Developer mode / unpacked installation, a fixed
public key for the unpacked ID, ad-hoc bundles installed by lampvm, environment
flags and predefined fixture scaffolding. No private signing key is committed.
Native messaging, optional permissions, persistent extension tabs and background
`tabs.create` are supported Chrome mechanisms. Store distribution, signing,
installer repair, other browsers and real service compatibility need separate work.

References: [native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging),
[optional permissions](https://developer.chrome.com/docs/extensions/reference/api/permissions),
[worker lifetime](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle),
[permission warning API](https://developer.chrome.com/docs/extensions/reference/api/management#method-getPermissionWarningsByManifest).
The main/article-first text approach was informed by
[Local's connector](https://github.com/RooCodeInc/local/blob/a64391f3b27535adb91aa12c60955e5514319fdc/browser-extension/background.js).

Keep screenshots, recordings, runtime grants, generated apps, test output and
independent adversarial proof outside git. Remove the two Store hooks,
BrowserPrototype.swift, BrowserTaskPrototype.swift and this folder to discard
the experiment.

## Show Lamp this task

The toolbar now opens the task recorder. **Manage app access** still reaches the
standing-access view. Task-recording site approvals are separate from app grants.
The person selects approved sites, pins the extension, and starts a task lasting
up to ten minutes. A REC badge stays in Chrome's toolbar, and approved pages have
an on-page recording bar with one-click Stop and Discard. Unpinning or removing
site permission discards the active recording. Only foreground top-level pages
on the selected origins send events; this is not desktop or video capture.

The captured record is deliberately small:

- Page origin and path, with query strings and fragments removed, page title,
  event kind, and relative time when Lamp receives the batch.
- Trusted clicks on links/buttons and field changes, with sanitized control
  labels. No entered field values or keyboard stream.
- Up to 1,500 characters of rendered page text per event, from main/article or
  the body. Input/select/textarea values, editable areas, hidden elements,
  `data-private` areas, scripts, styles, frames and the recording bar are skipped.
  Excerpts can still include sensitive business text shown by an approved site.
- No cookies, local storage, screenshots, audio, downloaded-file contents,
  Finder actions or other applications. Closed/background tabs are not observed
  by this task recorder, even though the earlier connector can read them.

Chrome holds a maximum 30-event pending batch in memory. `storage.session` keeps
only recording metadata; profile identity remains in `storage.local`. The
native bridge writes one current trace to
`Edition.supportFolder/BrowserPrototype/Tasks/recording.json`, in a private
user-owned folder. Stop freezes the trace and sends its events to Lamp's text AI
through OpenRouter; the start screen states this before recording begins. The
AI returns editable steps and exactly one app idea. Its answer and a small
model/cost receipt stay beside the trace. Discard stops capture, cancels any
pending analysis and deletes these local files; failed deletion is reported.
It cannot retract data already sent to the AI provider.

**Build** is the next explicit action. It creates a normal Lamp draft and sends
the reviewed request through `Store.send`, with a copy of the trace under the
new project's Attachments. This uses Lamp's existing builder/approvals/build
conversation for every engine. The source trace can be discarded later, but
the approved app's attachment and conversation remain with that app. The
inferred idea explicitly avoids browser connectors or continued observation;
the person supplies/imports data to the resulting standalone app.

For the fictional demonstration, `/task` offers insurance policy details and a
renewal shortlist. `/unapproved` is a second-origin exclusion canary. These are
made-up task fixtures, not recorded responses from an outside service. Analysis
and the normal build can use a real OpenRouter key in an isolated guest only
with explicit permission. Never commit or print a key, trace, AI reply or build
artifact. Environment flags, unpacked loading and VM-installed ad-hoc bundles
remain development workarounds; observation itself uses supported Chrome
scripting, messaging, host permission and action APIs.

The recorder does not resume a trace after Lamp/browser restart, does not infer
Finder work, and does not replay actions. It is an observation-to-build
experiment. Long-run recovery, shadow DOM, complex SPAs, account selection,
full-screen indicator behavior, onward AI-provider retention and hostile
same-user native apps need separate work. Plain prototype copy/layout is left
for a later design pass.

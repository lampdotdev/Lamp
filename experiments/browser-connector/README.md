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
   folder's `extension` directory. Pin the toolbar icon (Lamp) to use the task recorder.
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

The toolbar button opens a popup, the task recorder. **Apps that can read pages**
at its foot still reaches the standing-access view. Task-recording site approvals
are separate from app grants. The popup has one thing to do at a time:

- On a site Lamp may not watch yet, **Let Lamp Watch This Site**. Chrome's own
  question closes the popup, so the worker finishes the approval for the site that
  was asked about (`task-asking`, `permissions.onAdded`) and opens the popup again.
  Chrome asks only the first time it is asked about a site; after that it allows
  the site again without a question, even after **Remove**.
- With a site approved, what is noted, what never is, and that Stop sends the
  notes to Lamp's AI and can't be undone, above **Start Recording**. Only the site
  in front starts ticked. Start shows only once the extension is pinned.
- While recording, the time, **Stop and Show Lamp** and **Discard**.

**Remove** beside a site ends Lamp's approval and Chrome's permission for it,
unless an approved app still reads that site. A task is watched for up to ten
minutes (or 600 events). At the limit it pauses and asks: watching ends, the
recording stays on this Mac as it is, the bar and the popup offer **Show Lamp**
and **Discard**, the badge turns to an amber pause mark and the popup is opened
when Chrome allows it. Nothing is sent to the AI until the person chooses, however
long that takes; Lamp decides when the limit is reached (`pauseIfDue`) and drops
what arrives after it. `LAMP_BROWSER_TASK_LIMIT` (seconds) can shorten the limit
to see the pause without the wait; it cannot lengthen it.
A REC badge stays in Chrome's toolbar, and approved pages have a floating
recording bar (a closed shadow root, so a page's styles can't hide it) with the
time and one-click Stop and Discard. The bar is shown in the browser's top layer.
A modal dialog blurs and switches off everything outside itself, so while one is
open the bar is moved inside that dialog, the one place the browser leaves usable,
and moved back when it closes. Unpinning or removing site permission
discards the active recording. Only foreground top-level pages
on the selected origins send events; this is not desktop or video capture.

The captured record is deliberately small:

- Page origin and path, with query strings and fragments removed, page title,
  event kind, and relative time when Lamp receives the batch.
- Trusted clicks on what a page is worked with (links, buttons, tabs, switches,
  boxes, menu items and the roles sites give plain elements for them), with the
  control's name and, for a switch or box, whether it ended on or off. The click
  is read from its whole path, so one inside a component's shadow root is seen as
  the control it landed on, not as the component. A menu's chosen option is noted
  by name. A field is noted once when typed in, by name only; Return pressed in a
  field is noted, and no other key. No entered field values or keyboard stream.
- Back, Forward and Reload, from the browser's navigation records, for a new page
  and for a site that swaps its own content.
- Scrolling the person did, where it comes to rest and only when it went half a
  screen or more, with the text then in view. Scrolling inside a component's own
  shadow root is not seen: the browser doesn't pass it on.
- Up to 1,500 characters of rendered page text per event, from main/article or
  the body, read through components and their slots; an open dialog's text comes
  first. A site that shows back what was typed (a recent-searches list, "results
  for …") puts those words in this text: the field is never read, the page is. Input/select/textarea values, editable areas, hidden elements,
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
through OpenRouter; the popup says before recording begins that the notes go to
Lamp's AI and can't be taken back, without naming the service. The
AI returns editable steps and exactly one app idea, shown in Lamp as a numbered
list and a card for the idea, with the request Lamp would be given folded under it. Its answer and a small
model/cost receipt stay beside the trace. Discard stops capture, cancels any
pending analysis and deletes these local files; failed deletion is reported.
It cannot retract data already sent to the AI provider.

**Build This App** is the next explicit action. It creates a normal Lamp draft and sends
the reviewed request through `Store.send`, with a copy of the trace under the
new project's Attachments. This uses Lamp's existing builder/approvals/build
conversation for every engine. The source trace can be discarded later, but
the approved app's attachment and conversation remain with that app. The
inferred idea explicitly avoids browser connectors or continued observation;
the person supplies/imports data to the resulting standalone app.

For the fictional demonstration, `/task` offers insurance policy details and a
renewal shortlist. `/overlay` is a made-up catalogue built the way many real
sites are (a search component with a shadow root, opened as a modal dialog over a
blurred page, with a switch, a menu of boxes and a link to a long list), for
trying capture and the bar without loading anyone's site. `/unapproved` is a second-origin exclusion canary. These are
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
same-user native apps need separate work. The standing-access view
(`access.html`) still has its first plain layout.

## An app that does the shown task

**Build This App** now makes an app that does the task itself, on the site where it was shown, in a tab of
the person's own Chrome. Pressing it is the person's yes to that app using that site
(`BrowserRun.allow`, kept by the app's instance so naming the app doesn't lose it); the review says so in one
line, the popup lists the apps that may use each site, and **Remove** beside a site ends every app's use of it.
What was shown is kept with the app (`.lamp/shown-task.json`: the site, where it began, the reviewed steps and
what was used, by name) and the build request carries a note for the builder: the app asks with the
`LampComputer.ask` / `.perform` it already has, and for an app built this way Lamp answers through the browser
instead of the other apps on the Mac (`Store.useBrowser`).

The run is AI-driven: one more driver behind `ComputerUse.Job` (`BrowserRun.Driver`), so the limits, Stop, the
route the app's text goes along and the question before an action are that job's, for every engine. The AI is
given what was shown and works from it; it reads the page as a list of what can be used, each with an id, and
the text in view (`task-drive.js`), and uses one control at a time. Lamp, not the AI, decides what each step
is (`BrowserRun.verdict`): opening, searching, filtering, switches, boxes, menus and same-site links go ahead;
a button or form Lamp can't place, and anything whose name says it sends, buys, borrows, saves, deletes or
changes an account, waits for the person in Lamp's approval panel, one action at a time (no "Allow All"
here); `ask` refuses those outright. Links to other sites and password fields are never used.

The run works in a tab of its own, in front, with the bar saying which app is working and **Stop**. A page that
needs the person (a check that they are human, a sign-in page) is handed to them: the bar says so and offers
**Continue**; after five minutes with nobody there the AI answers with what it has and says what's missing.
Lamp never types into password fields or gets past those checks. A site that sends the tab elsewhere ends the
run with a plain message, and the AI says plainly when the site no longer has what the task used
("looks different from when you showed Lamp this task").

The page's own clicks (`element.click()`, events for typing and Return) are what an extension can send; a site
that only listens to clicks from a real person won't respond. The debugger permission, which could send real
input, is not used.

`/overlay/sign-in` and the **Reserve this lamp** button on `/overlay/item` are made-up pages for trying the
handover and the approval without anyone's account.


## App companions

The same extension can host a running app’s own companion in Chrome’s sidebar.
See [the companion design and app API](COMPANIONS.md) for the Recipes example,
access boundaries, lifetime and development workarounds.

import Foundation

/// The words for a request the model's provider refused as too big: the pictures in a conversation add up
/// (Anthropic takes 30 MB of them in one request).
extension Agent {
    static let droppingPictures = "The conversation holds more pictures than the AI can take in at once, so Lamp is dropping the older ones and trying again."
    static let conversationTooLarge = "The conversation had grown too large for the AI to take in at once, so Lamp has started a fresh one for this app. Send your request again."

    /// Whether an engine's failure is the provider refusing the request for its size (HTTP 413, Anthropic's
    /// payload_too_large, OpenAI's request_too_large, and Claude Code's own words for it), as against the
    /// context window, which the engines handle themselves by compacting.
    static func isRequestTooLarge(_ text: String) -> Bool {
        let lower = text.lowercased()
        if ["payload_too_large", "request_too_large", "payload too large", "request too large", "request entity too large",
            "pushed the request over the limit"].contains(where: lower.contains) { return true }
        return lower.contains("413") && (lower.contains("too large") || lower.contains("cannot exceed"))
    }
}

enum AgentEvent {
    case text(String)
    case textPiece(String) // a piece of the message the model is writing, as it streams in; `.text` follows with the whole
    /// A tool call as shown in the chat ("grep cache.json"), and the whole call with its arguments,
    /// which is what tells a repeated call from a similar one.
    /// `said`: what the agent said the step is for, in its own words (a command's description, a tool's `doing`).
    /// `id`: the engine's id for the call, which its outcome comes back with (`ended`); `command`: a shell command's
    /// text, as its row in the chat has it ("Ran: …").
    case tool(String, call: String, said: String? = nil, id: String? = nil, command: String? = nil)
    /// A tool call has finished, by the engine's id for it, and whether it failed (a command that exited with an
    /// error, a tool that answered with one).
    case ended(String, failed: Bool)
    case cost(Double)
    case failed(String)
    case raw(String)
    case session(String)   // an external engine's conversation id, to resume next turn
    case step(String)      // the model has started on a tool call (its name), or on text ("")
    case stepArgs(String)  // a piece of that call's arguments, as they stream in
    case compacted         // the engine summed up the conversation so far to make room
    case plan([PlanPart])  // the agent's plan, a new app's chapters in the chat
    case finished          // the engine has answered: a message written to it now would start another answer
    case received          // the engine gave the model a message of the person's (the request, or one sent mid-turn)
    /// Codex began (true) or finished (false) something it does on its own (a command, a tool call, an edit, a
    /// search), by its id: a Codex run is cut to pass a message on only between them (`Store.steer`).
    case acting(String, Bool)
    /// What the agent says it's doing, in its own words: Claude Code's or pi's description of a command, a Codex
    /// reasoning summary's heading. Empty for a command that came without one, which leaves it unnamed.
    case naming(String)
    /// A shell command Codex finished, or that was refused before it ran (`refused`), as the agent wrote it, and
    /// whether it failed. The step the person reads is named by `naming`; the command is shown only when the step is
    /// opened.
    case ran(String, refused: Bool, failed: Bool = false, id: String? = nil)
}

/// Drives the bundled pi coding agent (github.com/badlogic/pi-mono, MIT) in JSON mode.
/// pi only gets file tools: Lamp does the building and feeds compiler errors back.
enum Agent {
    /// `bash` only with Lamp's extension, which routes every command through the user's approval.
    static var tools: String {
        "read,edit,write,grep,find,ls" + (lampTools == nil ? "" :
            ",bash,web_fetch,look_at_app,use_app,plan,delete_file,list_versions,name_version,restore_version,make_art,offer_setup,make_app_for,remove_app,connectors,lampify,network_devices,device_integration,device_permission,ask,progress,write_wish,read_skill"
            + (Memory.isOn ? ",read_notes,save_notes" : ""))
    }

    /// Lamp's own tools for pi (Resources/lamp-tools.ts): `look_at_app` has Lamp build and open the app
    /// mid-turn and shows the agent the result; `plan` gives a new app's chapters in the chat; `delete_file`
    /// removes a file, which pi's own tools can't; the version tools list, name and restore the app's saved
    /// versions; `make_art` paints a picture for the app; `offer_setup` shows a setup card in the chat; `read_notes` and `save_notes` are Lamp's notes (Memory). Claude Code and Codex get the same tools from Lamp's MCP endpoint (Store.mcpTools).
    static var lampTools: URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("lamp-tools.ts")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// Rules for the tools every engine has: pi through Resources/lamp-tools.ts, Claude Code and
    /// Codex through Lamp's MCP endpoint (Store.mcp). Keep the two in step.
    static var tryRules: String { talkRules + findRules + lookRules + planRules + artRules + setupRules + connectorRules + githubRules + deviceRules + (Memory.isOn ? memoryRules : "") }

    /// For the engines whose shell commands run confined (Sandbox): what the shell can and can't reach.
    static let sandboxNote = """

    - Your shell commands run confined to the app's folder, plus the system, developer tools, caches and \
    temporary folders, with network access; the rest of this Mac is closed to them. What's closed doesn't \
    always say "Operation not permitted": it can look missing or broken instead ("No such file", "File \
    Doesn't Exist", an app that isn't found by name or bundle id). Closed to the shell: the installed \
    copy of this app, which it can open but not look inside, and ~/Library/Services, where Finder's Quick \
    Actions are. And `open -a App file` fails with error -10820 for an app that hasn't declared that \
    kind of file (`opens` in capabilities.json), whatever its code does. So "not found" or a failed open \
    there can mean "closed to you" or "not declared": never read it as a fault in the app's code. To \
    read a file elsewhere, use your file tools, which ask the user. `gh` can't see its sign-in there: \
    clone public repositories with `git clone --depth 1 https://github.com/owner/name .lamp/reference/name`; `lampify` \
    reaches a private one with the person's sign-in.
    """

    private static let lookRules = """

    - `look_at_app` puts what you've written into the app and shows you its windows, what it printed and any \
    build errors or crash, so you can check your work instead of guessing. What you save goes into the open app \
    by itself when it can; a look shows you what the person sees. While the app is open a look is quick, since \
    only the files you changed are compiled. Fix what you see before finishing.
    - Show the change early and bit by bit. The person is waiting beside the app, and a minute of nothing feels \
    long: your first look comes as soon as there's one thing to see, before you've read more than that one thing \
    needs, and a change with several parts is saved part by part, in the order they'd notice (a theme: the colors \
    first, then the type, then the symbols), each going into the open app as you save it, with a look when you \
    need to see how it came out; never written whole and looked at once at the end.
    - Work in passes when you build a new app, or when a request changes much of what the person sees in an app \
    they already have (a new screen, a redesign, a new main feature; not a fix or a small change), so they \
    watch it take shape instead of waiting for the end. Each pass leaves the app building and visibly further \
    along: first the layout, the window or screen with its real sections in place and placeholder content where \
    the detail will go, and nothing behind them yet (no saved data, no logic); then the main parts working, \
    with example data; then the detail: pictures, empty states, finishing touches. Two or three passes, four at \
    most. As each pass begins, call `progress` with what's in now and what comes next. End each pass with \
    `look_at_app`, which puts it into the open app, and fix what you see before going on. Never write the \
    whole thing before the first look: the first pass ends with a look before any of the logic is written. \
    In a new app, make what's read only at launch (the App, its scenes and menu commands) right in the first \
    pass, since changing it reopens the app, and later passes then go in while it stays open. In an app the \
    person already has open, it goes in the last pass instead, with the other changes that need a reopen, so \
    the passes before it go in live. Rough is fine until the last \
    pass: don't polish one before showing it. When a look says the change waits for Reload, nothing after it \
    shows until the person presses it: go on with the passes left, and your progress lines say they show after \
    Reload, never that they're in. When you need to see the app before going on, look: Lamp stops you there, you \
    say in a sentence that you need to see the change and ask for Reload, and Lamp starts you again after it.
    - `use_app` then uses the open app like a person: clicks, types, presses keys, scrolls and picks from menus, \
    and shows you the result. Both tools give you the front window as text beside its picture: every control \
    and piece of text, each with an id, its name, what it holds and where it is. Act on things by name: set \
    `target` to an id or exact name from that list (click a button or switch, type into a field, press a key \
    in it), and read the list for exact words and values rather than the picture. Use x and y only for what \
    the list doesn't have: a drawing, a canvas, a chart, a game board. A control the list shows with no name \
    has no accessibility label: give it one. Name what's drawn too: in a game or anything drawn in a Canvas or \
    SpriteKit, make each thing the person would point at (the ball, a piece, a character) an accessibility element \
    with its name, so it's in the list and the person can point at it from the chat. It tells you what each action did and whether the window \
    changed: when nothing changed, a click by point probably missed, so aim again before deciding the app is \
    broken. It uses the app as last built, so call `look_at_app` again after editing code.
    - Never open the print panel while trying an app (a Print button, File > Print, ⌘P): it makes macOS ask \
    the person, over whatever they're doing, whether the app may look for devices on their network. Check \
    what would be printed from the code or another screen, and say that printing itself wasn't tried.
    - A new app is open in front of the person while you build it (from the start, or from your first look), \
    with the chat beside it, so they watch each pass go in. Once the last pass looks right, stop there: say in one sentence what they now \
    have, and don't describe the app further.
    - Look at the app, don't test it: never click around in it (`use_app`) unless the person asks you to try \
    it. They're probably using it, and your clicks, keys and windows get in their way. Check a change with \
    `look_at_app` and by reading the code, and fix what you see. Say what wasn't tried in one plain sentence, only for a change to what the app does \
    (a button's effect, a form, saving). \
    When they ask you to try it, walk through the main things they asked for with `use_app` as they would \
    (add an item and see it appear, fill the form and submit it, quit and reopen to see what was kept), fix \
    what you find, and say in one plain sentence what you tried and what happened. They watch you try it and \
    can take it back at any moment: when `use_app` says they took the app over, leave it to them for the rest \
    of this request, and say in one plain sentence what's left for them to try.
    """

    /// Every engine has these too (pi's extension, Lamp's MCP endpoint). Kept apart from the look rules only
    /// because the prompt reads better in that order.
    private static let planRules = """

    - When you build a new app, call `plan` once, before writing any code, with its 3 to 5 main parts in the \
    order you'll build them, in the user's own words (what they'll be able to do, never file or type names) \
    and, for each part, the files you'll write for it. Lamp ticks a part off when its files are written, so \
    the user watches the list fill in while they wait. The parts follow the passes: the first is the window \
    and its layout (the App and its views, with placeholders), and what later parts rely on (the app's saved \
    data, a connection to a service) belongs to the first part that uses it after that. Write the files part by \
    part in the list's order, so it fills in from the top and never looks as if a part was skipped. Give every \
    file to exactly one part: the one that first writes it. Don't use it for small changes.
    - `delete_file` removes a file the app no longer needs, for example after moving its code elsewhere or \
    removing a screen. Never leave an emptied file behind instead.
    - Lamp saves a version of the app after every request. `name_version` names one so the user can find it \
    later: name the version this request makes after a milestone the user is happy with, or name the current \
    one (its id from `list_versions`) before a big or risky change, e.g. “Before the redesign”. \
    `restore_version` brings back an earlier version's files: use it only when the user asks to go back, \
    never to undo your own attempt, and find the version with `list_versions` first.
    """

    /// The pictures an app's kind calls for (companion, collection, game), painted while building rather than
    /// drawn in code, in the icon's style so they match it.
    /// The pieces the agent talks with (Talk): what each is for is in its tool's description, so this says only
    /// that they come before prose, and how an answer returns.
    private static let talkRules = """

    - You talk to the person in cards and short sentences of 15 words at most, never in paragraphs, lists, \
    headings or bold, and never in words that repeat what a card says. Your pieces: \
    `ask` for anything you need to ask (they click an answer, type their own, or leave it to you); \
    `plan` for what \
    you're building; `progress` for a line on how longer work is going; `offer_setup` for setting up AI; `make_app_for` when they want the app on other devices \
    (the iPhone, the Mac or a TV), and `remove_app` when they want one of the wish's apps gone. A change of mind \
    ("never mind, make it a timer instead") changes the app the wish has, in its own code and, when what it's made for \
    changes, with `make_app_for` and its folder in `app`; one more app of another kind ("an Android app as well") is \
    `another`, only once they chose it when you asked them with `ask`, before changing anything; two apps of one kind \
    (two Mac apps) can't be in a wish yet: the `more-apps` skill. When a piece fits, use it instead of writing the same \
    thing out: no questions, options or assumptions listed in a reply. A click comes back as their next \
    message, the same as something typed. If they type something that isn't one of your options, that's their \
    answer: follow it.
    - What the person sees: their messages, your cards, and each thing you write, as a message the moment you \
    write it. Your tool calls are never shown: no commands, files, code or results, only a gray line per step \
    ("Did a bit of housekeeping", or the words you gave the step: a command's description, a tool's `doing`). Give \
    those words to every step, in their terms, since they're what the person reads while it runs. Everything you write stays in the chat as a \
    message, and your last one is the answer. So write each message for someone who sees nothing else: it makes sense on its own and is about the app, \
    never leaning on a step they can't see, whether it leads into one, points back at one ("that fixed it", \
    "the error above") or names its files and code.
    """

    /// "Help me find one" on Lamp's desk starts a wish with this request (`LampProject.finding`).
    static let findingRequest = "Help me find something to wish for."

    private static let findRules = """

    - When the person asks you to help them find something to wish for, nothing is built yet: change no files. \
    Find it with them like a short wizard, in `ask` cards: first which of four everyday moments sounds like them, \
    each a situation from a different part of life (home, family, health, money, work, play) in plain words, such \
    as "Checking if a delivery is close"; then one or two questions about the one they pick: who it's for, when it \
    comes up, and where help would suit them (their Mac, iPhone or watch, the menu bar, a widget, or quietly in \
    the background). Ask about their days, never about apps. Then call `write_wish` with the wish in their words, \
    as a request to Lamp, and end. They send it, changed or not: that message is the wish. Build it then, \
    without asking again.
    """

    private static let artRules = """

    - `make_art` paints a picture into the app's Assets/ folder, in the same style as its icon: one object on a \
    transparent background, or a whole scene. Show it with `LampAssets.image("name.png")`. Use it where the app's \
    kind calls for art, never for icons on buttons or anything an SF Symbol shows. Each picture takes a while and \
    costs the user: make only what the design needs. For something that fills, grows or ripens, paint it once, \
    complete (the full glass, the ripe tomato), and show how far along it is in code: the complete picture masked \
    to the progress over a faint or outlined copy, so it reads as empty at zero; never paint the empty state too. \
    Look at each picture before using it (call it again with a better subject if it's wrong). When nothing can make pictures, use \
    SF Symbols in the app's palette instead, never a picture drawn in code: Lamp offers the user a way to set that up.
    """

    /// Rides with a message the person sent while the agent worked (`Store.handOver`), not in the system prompt:
    /// a rule there about such messages was followed only some of the time, and a message answered with nothing
    /// reads in the chat as if it was never heard.
    static let midTurnNote = """


    Note from Lamp: the person sent this while you were working. Before your next step, reply to it in one \
    short sentence that shows you heard it and says what you'll do now ("Got it, the theme: I'll change the \
    colors and type across the app."), then carry on with it in mind.
    """

    /// With each request to an app that's updated in place (LiveReload): which changes keep it open. Here and
    /// not in the system prompt, since it depends on the app's kind.
    static let liveNote = """


    ---
    The person has this app open beside the chat and is watching it as you work. A change that goes into the \
    open app shows at once; one that can't waits until they press Reload, and until then they see nothing of it. \
    So work in small steps, each shown with a look as it lands, prefer the shape of change that goes in live, and \
    say what they can see now, not what you've written. Each look tells you which way the change went and why. \
    What you save goes into the open app by itself a few seconds after you save it, whenever it can, so the person \
    sees each piece as you write it. But changes saved close together go in together, and one that can't go in \
    live holds back everything saved with it: so save the most visible piece first and alone (a theme: the file \
    with its colors), in a step of its own, and look before you save anything else; after that, each piece goes in \
    by itself, with no need to wait for a look. \
    Once a change in a request has to wait for Reload, nothing more shows until they press it: go on with what's \
    left, saying in progress lines what shows after Reload and never that it's in, and when you need to see the \
    app before going on, look, and Lamp stops you there until they've pressed Reload and starts you again after. \
    So plan the request before you write: make the changes that go in live first, with a look after each, and put \
    every change that needs the app reopened at the end, all together, or leave it for a request of its own, so a \
    request ends with one Reload at most. Before the first change that needs a reopen, look, and start those \
    changes only once the look says what you saved before them is in the open app. These need it reopened: the app's icon (icon.json), capabilities.json, a \
    widget or Share item, what's read only at launch (the App, its scenes, window titles and menu commands), new \
    stored properties in a Codable class, and the other changes below that say so. The icon matters least: save \
    icon.json in that last group, then paint any new pictures, which take its colors. \
    This app is updated in place while it's open, keeping what's on screen, when a change only edits or adds code. \
    A body whose structure changes (a modifier or a view added around others) is built again, and the @State and \
    @StateObject of the views inside it start over, so keep what must survive in a model those views read. \
    A change to a Shape's path, or to an NSViewRepresentable's or UIViewRepresentable's make or update, shows only \
    when SwiftUI next draws that shape or updates that view; if the person must see it now, look with reopen. \
    New stored properties go in too, in a class, a struct or a view (as @State, @AppStorage or a parameter its parent \
    passes), when each has a starting value (or is an optional, or a view's parameter) and no didSet or willSet, and the \
    type isn't a Codable class (a view's new @Environment(\\.key) and @Binding go in, an @Environment(Type.self) needs a reopen); so do new cases at the end of an enum whose cases carry nothing, \
    and new values for constants that hold no object, and a stored property removed or renamed, except in a type \
    that is Equatable, Hashable or Codable. Changing a stored property's type, a case anywhere \
    else, or what's read only at launch (the App, its scenes and menu commands) needs it reopened, which waits \
    for the person to press Reload. \
    Code already running keeps the version it started with: a closure given to a Timer, a Task or an observer, a \
    Combine sink, a view's .task (what a view's body makes, a Button's action or .onReceive, is made again). So in a \
    loop or a timer, call a method of the app's each time rather than writing the work in the closure, and a change \
    to that method goes in; make that method internal, not private or fileprivate, since a private one is called \
    directly and stays as it was. A property added in place isn't saved until the app reopens. A method, computed property or \
    initializer added to a class that something subclasses needs the app reopened; a class nothing subclasses takes \
    methods and computed properties in place. A new starting value for a `static var` or global `var` needs the app \
    reopened, since the open app made its value once; a `let`'s goes in place, and so does a `let` made by \
    a function that changes (`static let table = build()`), unless it holds an object. Making a type or a static \
    private, or no longer private, needs it reopened, and so does changing a type's hash(into:). \
    Any change to a file that declares a SwiftData @Model class needs it reopened. \
    A look shows the window as the person left it, with the change in it. To see the app start from the \
    beginning (how long it takes to open, what runs once at launch), look with `reopen`, which asks the person \
    first while they have it open; never quit or kill the app yourself.
    """

    /// Short for the same reason. What AI the app has comes at the end of a request (AIStatus.brief), since it
    /// changes between turns.
    private static let setupRules = """

    - The end of a request says what AI this app can use right now: text, decisions and pictures, each with \
    what answers it, or "nothing can answer yet". Build for what's there. When a feature needs one that \
    isn't set up, or would be clearly better with one that only works a slower way, build it anyway, have \
    the app check `LampAI.isAvailable` and say so where the feature is, and call `offer_setup` once: Lamp \
    shows the person how to set it up. Never ask for keys or send them to Settings yourself.
    """

    /// Which services there are and how to build on each is the tool's answer (Connectors), so this stays one
    /// rule however many there are.
    private static let githubRules = """

    - When a request names a project on GitHub, open the github-projects skill with `read_skill` and do what the request \
    asks. To make an app from it, read it in a git clone as the skill says and call `lampify` before using any of its \
    code or assets, and again when the app is done. A project the person names is that project, with its author's \
    credit: never rewrite it from memory in its place.
    """

    private static let connectorRules = """

    - When a wish needs a service the person uses (their Notion, Airtable, GitHub, Home Assistant…) that the \
    accounts on this device can't reach, or open data from the web (weather, exchange rates, food products), \
    call `connectors` before writing code for it, and build on what it says. Never ask for a \
    key or a token in the chat or put one in the code: the app's own button asks the person. For a service that \
    isn't listed and needs a key, declare it with `LampAPI.own` (LampAPI's comment in LampSupport.swift) and put \
    `LampAPIButton` in the app, so the person gets the same Connect sheet: never a key field or dialog of your \
    own, and never UserDefaults, LampStore or a Keychain item.
    """

    /// How a device Lamp has no kit for is taken on: the integration's format is the skill's, so this stays short.
    private static let deviceRules = """

    - When the person asks to set up a device Lamp doesn't know, or a wish is for one, open the `device-integrations` \
    skill and hand Lamp the device's integration with `device_integration` before writing any app for it. Lamp finds, \
    checks and sets up the device itself, and draws every step's card: never walk the person through its steps in your \
    own words, and never try to reach the device with a command of yours.
    - When a wish controls, plays to or reads devices on the person's network (a remote, buttons for the speakers, \
    what's playing on the TV), or the person asks what something on their network is, call `network_devices` before \
    asking what they have, and start from what it finds: \
    "I see a Samsung TV, a Roku and a Sonos speaker." Ask only about what it can't tell you. Open the `device-control` \
    skill before writing code that reaches one of their devices. Reading a device is fine; change nothing on a real one \
    (a key press, opening an app, volume, power) until the person allows it with `device_permission`.
    - When `make_app_for` refuses, it says whose limit it is, and so do you, in your own words. When the device can't \
    run it (a 3D game or a web page on a Roku), say so about the device ("A Roku only runs its own channels, worked \
    with the remote, so it can't show this 3D game"). When the refusal says Lamp can't build it yet (a native app on a \
    Samsung or LG TV, a page on Vision Pro), say that Lamp can't make that yet, never that their device can't run it. \
    Then offer the nearest thing that works with `ask`: a simple version made for that device as one more of the \
    wish's apps, or another of their devices the refusal says runs it, or casting from a phone. Never pass on a tool's \
    error as it came, or explain how Lamp works inside: what reaches the person is what's true of their device, of \
    Lamp and of their wish.
    """

    /// With every request in a device's setup conversation: the conversation outlives what it began with, and a
    /// follow-up ("it still says waiting") is about the device, never a wish.
    @MainActor static func deviceSetupNote(_ project: LampProject) -> String {
        var note = "\n\n---\nThis conversation is the setup of a device of the person's (from Lamp, not part of the request above): no app is made here. Write no files and open nothing; write or fix the device's integration with `device_integration` (the `device-integrations` skill), and answer about the device in a sentence or two. Lamp shows its setup steps as cards. When the person wants something on the device, tell them to make a wish for it on Lamp's desk."
        // What the device said of itself when it was found, for writing its integration: the agent's to read, not the
        // person's, so it isn't in the request they see.
        // A device Lamp doesn't know is kept by its network address in the list, and by its hardware address too here.
        let setup = project.deviceSetup
        // One begun without a hardware address can't be told from whatever has its address now: nothing found is said of it.
        let unverified = setup.flatMap(Device.foundAddress) != nil && setup.flatMap(Device.foundHardware) == nil
        let device = unverified ? nil : Store.shared.devices.first { $0.id == setup }
            ?? setup.flatMap(Device.foundAddress).flatMap { address in
                // Only while the same hardware is at that address.
                guard let hardware = setup.flatMap(Device.foundHardware), Neighbours.table()[address] == hardware else { return nil }
                return Store.shared.devices.first { Device.foundAddress($0.id) == address }
            }
        if let device {
            var said = [device.maker, device.model].filter { !$0.isEmpty }.joined(separator: " ")
            if !device.modelID.isEmpty { said += " (model number \(device.modelID))" }
            note += " Lamp found it on the network as \(said)" + (device.discovery.map { "; it answered Lamp's scan as \($0)" } ?? "") + "."
        }
        // Its host's facts, for working out what it is and how it's reached: all there is for one set up from Everything
        // Else, which may be something Lamp can't reach at all (say so plainly then). The names it goes by on the network
        // are often people's, so they stay out of the integration.
        let address = device?.address ?? project.deviceSetup.flatMap(Device.foundAddress)
        let hardware = project.deviceSetup.flatMap(Device.foundHardware)
        // A device found on the network is the host with its hardware address; one whose setup began without that
        // can't be told from whatever has its address now, so no host's facts go with it.
        let isFound = project.deviceSetup.flatMap(Device.foundAddress) != nil
        if let host = Store.shared.hosts.first(where: { $0.address == address && (isFound ? hardware != nil && $0.mac == hardware : true) }) {
            if device == nil { note += " Work out what it is first, from what Lamp found of it, and tell the person; if nothing on the home network can reach it (it's controlled only through its maker's cloud, or has no local interface), say so in a sentence rather than writing an integration." }
            note += " Its host: " + HomeNetwork.facts(host) + ". Keep the names it goes by out of the integration: find it by its service, maker or model."
        }
        // The last test run on it: what the device did with an app made from the integration, which the builder fixes.
        if let deviceID = project.deviceSetup, let report = IntegrationProbe.report(for: deviceID) { note += "\n\n" + report }
        return note
    }

    /// The first request of a device's setup conversation, from Set Up… on a device Lamp doesn't know
    /// (`Store.setUpDevice`), in the person's words: what Lamp found of it goes to the agent in `deviceSetupNote`.
    static func deviceSetupRequest(_ device: Device) -> String {
        "Set up my \(device.plainName)."
    }

    /// Kept short, like the tools' descriptions: every word here is sent with every call to the model. What the
    /// notes cover comes at the end of a request (Memory.brief); the notes only when the agent asks.
    private static let memoryRules = """

    - Lamp keeps notes about the person and about this app between requests (`read_notes`, `save_notes`), and \
    tells you in a line what they cover. Read them before you build a new app or a new screen, and whenever \
    a request touches what they cover; not otherwise, since reading costs the person. Follow them, but what \
    the person asks now wins: do that and correct the note. Before you finish each request, ask yourself \
    whether it showed you something that should hold next time: they corrected you, said what they like or \
    don't, turned something down, or put it as general (“in anything I use”, “I can't stand…”). If so, save \
    it then; they needn't say "remember". How to go about this one request (“don't test it”, “be quick”) is \
    not that: it is an instruction for now, not a taste, and isn't noted about them or the app. If nothing \
    lasting came up, save nothing. \
    Lamp shows the person in the chat what you noted, so don't mention the notes yourself unless asked.
    """

    /// pi ships inside Lamp.app (see build.sh).
    static var executable: URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("pi/pi")
        return url.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

    /// Lamp's own pi settings and caches, separate from any pi the user runs themselves.
    static let configDir = Edition.supportFolder.appendingPathComponent("pi").path

    /// The rules for the app's kind. Most are the same for a Mac app and an iPhone app, and each kind adds the
    /// blocks only it has, so a building block given to one is described to both in one place.
    /// A wish with other parts gets one rule more, naming them (`Parts.rule`); their own rules are skills, opened when
    /// the agent works on them. A wish whose apps are all in folders of their own has no kind's prompt of its own but the
    /// wish's (`wishPrompt`). A wish still to be told what it's for gets no kind's rules at all (`undecidedPrompt`).
    @MainActor static func systemPrompt(for project: LampProject) -> String {
        if let candidates = project.undecided { return undecidedPrompt(candidates: candidates) }
        let parts = Store.shared.parts(of: project)
        guard project.holdsApp else { return wishPrompt(for: project, parts: parts) }
        return kindPrompt(for: project) + Skills.forDevices(of: [project] + parts) + Parts.rule(for: project, parts: parts)
    }

    /// The prompt of a wish whose apps are all in folders of their own: what holds for the wish as a whole (asking, the
    /// shell, its icon and description, attachments, how to talk and finish), then its apps. A wish of one such app has
    /// that app's rules here, for the files in its folder; a wish of several has each app's as a skill, as any wish's
    /// other apps have (`Parts.rule`), so no app of it comes first.
    static func wishPrompt(for wish: LampProject, parts: [LampProject]) -> String {
        guard !parts.isEmpty else { return emptyWishPrompt }
        let apps = parts.map { "\(Parts.name(of: $0)) in \($0.dir.lastPathComponent)/" }
        let header = """
        You are Lamp's builder agent. The current directory is a wish: \(apps.joined(separator: " and ")), each app in a \
        folder of its own with its own build files. The folder itself holds what's the wish's: its icon, its description \
        and the person's attachments. Read the APP.md in each app's folder first for context.
        """
        let rules = [Rules.ask, Rules.shell, Rules.icon, Rules.about, Rules.wishAttachments, Rules.audience, Rules.begin, Rules.finish]
            .joined()
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "builds each app you changed and opens it")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a Mac, a phone or a TV")
        // One app on its own is told nothing of reaching others, as an app in its wish's own folder isn't.
        let each = parts.count == 1
            ? parts.map { "\n\n" + Parts.pack(for: $0.platform, in: $0.dir.lastPathComponent, alone: true, integration: Parts.listedIntegration(of: $0)) }.joined()
                + (Template.talksToOtherApps(wish) ? Rules.wishTalk : "")
            : Parts.rule(for: wish, parts: parts) + Skills.index(Skills.everywhere)
        // Each app's devices offer their skills (a TV's design) in the wish's prompt, which is every app's.
        let devices = Skills.forDevices(of: parts)
        return header + "\n\nRules:\n" + rules + each + devices
    }

    /// The prompt of a wish with no app at all (its last one taken away): only what holds for the wish as a whole, and
    /// how it gets an app, with nothing of any kind's rules or files that are gone.
    static var emptyWishPrompt: String {
        let header = """
        You are Lamp's builder agent. The current directory is a wish that has no apps now: it keeps its name, its chat, \
        its history, its icon and the person's attachments, and nothing in it is built, opened or tried. When the person \
        wants something made, give the wish an app with `make_app_for`: what it is (`kind`, a game or an app), how it's \
        made (`made`) and the devices it's for; its reply carries that app's rules, which you then follow in the same \
        request. Undo in the chat's toolbar, or restore_version, brings back an app the wish had.
        """
        let rules = [Rules.ask, Rules.shell, Rules.icon, Rules.about, Rules.wishAttachments, Rules.audience, Rules.begin, Rules.finish]
            .joined()
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "builds each app you changed and opens it")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a Mac, a phone or a TV")
        return header + "\n\nRules:\n" + rules + Skills.index(Skills.everywhere)
    }

    static func kindPrompt(for project: LampProject) -> String { project.platform.target.guidance.prompt(project) }

    static let systemPrompt = prompt(platform: .mac, device: "Mac")

    static func iPhonePrompt(for family: DeviceFamily) -> String { prompt(platform: .iphone, device: family.name) }

    /// An app for both gets both kinds' rules, each said to be for its half, after one rule on how the halves
    /// share one code: so a block or a design given to one kind is given to the pair in the same place.
    static func universalPrompt(for family: DeviceFamily, part: String? = nil, alone: Bool = false) -> String {
        func half(_ place: String, _ rule: String) -> String {
            let lines = rule.split(separator: "\n", omittingEmptySubsequences: false)
            guard let first = lines.firstIndex(where: { $0.hasPrefix("- ") }) else { return rule }
            var changed = Array(lines)
            changed[first] = "- \(place): " + changed[first].dropFirst(2)
            return changed.joined(separator: "\n")
        }
        let onMac = "On the Mac", onPhone = "On iPhone and iPad"
        let wishRules = part == nil
        var rules = [Rules.edit] + (wishRules ? [Rules.ask, Rules.shell] : []) + [Rules.universal, Rules.universalFrameworks,
                     half(onMac, Rules.macBlocks), half(onPhone, Rules.iPhoneBlocks),
                     half(onMac, Rules.finder), half(onMac, Rules.menuBar), half(onMac, Rules.permissions),
                     Rules.script, Rules.intents, half(onMac, Rules.macAccounts), half(onPhone, Rules.iPhoneAccounts),
                     half(onPhone, Rules.iPhoneHardware), half(onPhone, Rules.iPhoneWidget), half(onPhone, Rules.iPhoneWatch), Rules.share, Rules.store, Rules.kinds(mac: true), Skills.index(Skills.offered(.universal)),
                     half(onMac, Rules.macDesign), half(onPhone, Rules.iPhoneDesign), Rules.macGenerated,
                     Rules.icloud, Rules.ai]
        rules += (wishRules ? [Rules.icon, Rules.about, Rules.attachments] : []) + [Rules.logs, Rules.universalTry]
        rules += wishRules ? [Rules.appMd, Rules.audience, Rules.begin, Rules.finish] : alone ? [] : [Rules.partTalk(mac: true)]
        let header = part.map { Rules.partHeader("an app for the Mac and for iPhone and iPad, one SwiftUI code for both (a Swift Package, Swift 5.9 language mode, macOS 14+ and iOS 17+)", folder: $0) }
            ?? Rules.universalHeader
        return (header + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: family.name)
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a Mac or an iPhone")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "builds it and opens it where Try On points")
    }

    /// `part`: the folder of a wish's other part this is for (`Parts.pack`): the rules of its kind alone, without the
    /// ones about the wish as a whole (asking, the shell, the icon, how to talk and finish), which the wish's own prompt has.
    /// `alone`: it's the wish's only app, so nothing about reaching the others.
    static func prompt(platform: Platform, device: String, part: String? = nil, alone: Bool = false) -> String {
        let mac = platform == .mac
        var rules = [Rules.edit] + (part == nil ? [Rules.ask, Rules.shell] : []) + [
                     mac ? Rules.macFrameworks : Rules.iPhoneFrameworks,
                     mac ? Rules.macBlocks : Rules.iPhoneBlocks]
        if mac { rules += [Rules.finder, Rules.menuBar, Rules.widget, Rules.share, Rules.permissions] }
        rules += [Rules.script, Rules.intents, mac ? Rules.macAccounts : Rules.iPhoneAccounts]
        if !mac { rules += [Rules.iPhoneHardware, Rules.iPhoneWidget, Rules.iPhoneWatch, Rules.share, Rules.icloud] }
        rules += [Rules.store, Rules.kinds(mac: mac), Skills.index(Skills.offered(platform))]
        rules += [mac ? Rules.macDesign : Rules.iPhoneDesign, mac ? Rules.macGenerated : Rules.iPhoneGenerated, Rules.ai]
            + (part == nil ? [Rules.icon, Rules.about, Rules.attachments] : []) + [Rules.logs]
        if !mac { rules.append(Rules.iPhoneTry) }
        if part != nil, !alone { rules.append(Rules.partTalk(mac: mac)) }
        rules += part == nil ? [Rules.appMd, Rules.audience, Rules.begin, Rules.finish] : []
        let header = part.map { Rules.partHeader(mac ? "a Mac app (a standalone macOS SwiftUI app, a Swift Package, Swift 5.9 language mode, macOS 14+)"
                                                     : "an iPhone and iPad app (a SwiftUI app, a Swift Package built for the iOS Simulator, Swift 5.9 language mode, iOS 17+)", folder: $0) }
            ?? (mac ? Rules.macHeader : Rules.iPhoneHeader)
        return (header + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: device)
            .replacingOccurrences(of: "{{A_DEVICE}}", with: mac ? "a Mac" : "an iPhone")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: mac ? "builds it and puts it into the open app" : "builds it and opens it in the simulator")
    }

    /// One rule each, ending in a newline. `mac…` and `iPhone…` pairs say the same thing for each kind of app;
    /// the rest hold for both, with `{{…}}` for the words that differ.
    enum Rules {
        static let macHeader = """
        You are Lamp's builder agent. The current directory is a standalone macOS SwiftUI app \
        (Swift Package, Swift 5.9 language mode, macOS 14+, no Xcode project). Read APP.md first for context.
        """

        static let universalHeader = """
        You are Lamp's builder agent. The current directory is a standalone SwiftUI app for the Mac and for iPhone and \
        iPad, one code for both (a Swift Package, Swift 5.9 language mode, macOS 14+ and iOS 17+; Lamp keeps an Xcode \
        project of its own for the builds). Lamp opens it on the user's Mac, in the {{DEVICE}} simulator or on their own \
        phone, whichever Try On points at, and that is what the user sees. \(phone) Read APP.md first for context.
        """

        static let universal = """
        - One code for both. Everything that can be shared is shared: the model, the data, the views; what differs \
        goes under `#if os(macOS)` and `#if os(iOS)`, kept small and close to where it differs (a scene's \
        `.commands`, a toolbar's placement, a menu bar item, a gesture). Never two apps side by side, never a file \
        per platform when a block will do. The rules below marked "On the Mac" apply inside the Mac's blocks and \
        the rest of the Mac's code; those marked "On iPhone and iPad" inside iOS's. The Mac-only building blocks \
        (folders, shortcuts that work in every app, the menu bar, the clipboard watcher, Mail, other apps, the \
        permission screens, opening at login) exist only under `#if os(macOS)`; `LampMotion` and `LampHome` only under \
        `#if os(iOS)`; `LampImage` is NSImage on the Mac and UIImage on iOS. Its widgets and Live Activities are \
        the iPhone half's (below); the Mac half has none, and Widget/Shared/ is compiled into the Mac half too, so \
        an `ActivityAttributes` type or a `LiveActivityIntent` there goes under `#if os(iOS)`. Check both halves compile before a look: \
        `swift build --product` and the app's name (the first target in Package.swift) for the Mac's, and \
        `./build.sh ios` for iOS's (it builds into build/iOS, beside the Mac's build).
        """

        static let universalFrameworks = """
        - Write code that compiles first time on both: only Apple frameworks, no third-party packages, APIs \
        available on macOS 14 and iOS 17, AppKit only under `#if os(macOS)` and UIKit only under `#if os(iOS)`. \
        One `WindowGroup`. Package.swift and build.sh belong to Lamp and are written afresh before every build, so an \
        edit to either is lost: no dependencies, plugins, compiler flags or build steps; everything the app needs \
        goes in Sources/.
        """

        static let icloud = """
        - To keep the person's data the same on every device signed in to their iCloud account, open the \
        icloud-sync skill before writing it, and follow it: it's kept with LampSync, not LampStore, and some data \
        may never sync.
        """

        static let universalTry = """
        - `look_at_app` builds the app for where Try On points (this Mac, or the {{DEVICE}} simulator) and shows you \
        it there; `use_app` works on the same. You can't move it yourself: when a change is for the other half, say \
        so plainly and ask the user to switch under Try On if they want you to try it there, and check that half \
        by building it instead. Everything the Mac and iPhone rules say about trying an app holds for its half; \
        the iPhone half's log and pictures are in .lamp/runtime/ios/ instead of .lamp/runtime/.
        """

        static let iPhoneHeader = """
        You are Lamp's builder agent. The current directory is a standalone SwiftUI app for iPhone and iPad (a Swift \
        Package built for the iOS Simulator, Swift 5.9 language mode, iOS 17+, no Xcode project). Lamp opens it \
        in the {{DEVICE}} simulator on the user's Mac, which is what the user sees, so design for the {{DEVICE}} \
        first while keeping the other usable. \(phone) Read APP.md first for context.
        """

        /// Installing on the person's own phone and looking in the simulator, shared by both iOS prompts.
        static let phone = """
        Lamp can build, sign and install the app on the person's own iPhone or iPad, the one chosen under Try On, \
        with a free Apple account; Apple signs iCloud, NFC, Siri, its weather and Time Sensitive notifications only for a \
        paid Apple Developer membership, and the request's device line says when the person's team is a free one. To open the app \
        on a phone, the person connects it, chooses it under Try On and presses Play. Your looks at the iPhone app \
        are in the simulator. An iPhone preview result includes a note about the Try On selection and Lamp's \
        device lookup once per turn, after the simulator app opens.
        """

        static let edit = """
        - Make the change the user asks for by editing files under Sources/. Split code into files as it grows.
        """

        static let ask = """
        - A vague wish is your cue to make a good first attempt, not to ask. Guess what it leaves open (who it's \
        for, what goes in it, what it remembers), choose what suits most people, and build: they'll change it as \
        they use it, and a wrong guess costs one more request. Ask before building only when one answer would \
        make a different app: whether it's useful at all, what it needs to reach (their calendar, contacts, an \
        account), what it costs them, or whether it acts outside the app (sends, books, writes to a calendar). \
        Then ask that one thing with `ask` (`steps`, one question), its likely answers lowest-impact first; \
        if they leave it to you, take that first one, such as suggesting times rather than adding them. Change \
        no files until the answer comes; if it opens another such question, ask that too. An answer chooses \
        what to build and nothing more: the app still asks for access and confirms each outside action itself. \
        For a change to an app that exists, ask only when it is too vague to build well; most are clear, so \
        build them. Ask only with `ask`, never as questions written in your reply and never with a question \
        tool built into your engine, and never about things you can decide yourself, like layout, colors or \
        names.
        """

        static let shell = """
        - You can read, search and edit files and read web pages without asking. You can also run shell commands \
        (to clone a repo, convert data, run a script); Lamp may ask the user to approve them. Never use the shell to \
        read, list, search or edit files (no cat, ls, head, grep, find, sed or heredocs): use your file tools for that, which need \
        no approval. Save the shell for what the file tools can't do. Lamp builds the app: never open or \
        run it yourself, and build it only where a rule here says to check that it compiles. When you finish, Lamp \
        {{RELAUNCH}}, and if the build fails your next message will contain the compiler errors to fix. If \
        something you need is denied or unavailable, say plainly what you need (for \
        example "attach the files"); a refused command is final, so never say the user will be asked to approve it. \
        Never tell the user to approve prompts or change \
        permission settings anywhere else: Lamp is the only place they can approve anything.
        """

        static let macFrameworks = """
        - Write code that compiles first time: only use Apple frameworks (SwiftUI, AppKit, Foundation, etc.), \
        no third-party packages, and APIs available on macOS 14. Package.swift and build.sh belong to Lamp and \
        are written afresh before every build, so an edit to either is lost: no dependencies, plugins, compiler \
        flags or build steps; everything the app needs goes in Sources/ (a widget's code in Widget/, a share extension's in Share/).
        """

        static let iPhoneFrameworks = """
        - Write code that compiles first time: only Apple frameworks (SwiftUI, UIKit, Foundation, MapKit, \
        AVFoundation and the rest), no third-party packages, APIs available on iOS 17, nothing from AppKit. One \
        `WindowGroup`; the app is built for iPhone and iPad. Package.swift and build.sh belong to Lamp and are \
        written afresh before every build, so an edit to either is lost: no dependencies, plugins, compiler flags \
        or build steps; everything the app needs goes in Sources/.
        """

        static let macBlocks = """
        - LampSupport.swift has tested building blocks for common Mac jobs: notifications, schedules, text from \
        documents and pictures, dropped files, watched folders, shortcuts that work from any app, the clipboard, \
        opening at login, photos, location, weather, music, Spotlight, the devices on the home network and the person's Roku. Use them instead of writing your own, and \
        open the building-blocks skill before using one. Make the most of being on the Mac: local files, drag and \
        drop, the menu bar, keyboard shortcuts, and fitting into what the user already does.
        """


        /// A share extension: the Share/ folder, built like a widget (`Template.hasShare`). How to write one, and what's
        /// different for each kind of app, is the share-extension skill.
        static let share = """
        - When the app collects things people find in other apps (links, articles, recipes, photos, receipts, \
        quotes), give it a share extension, so it's in their share sheets and takes things in without being \
        opened: open the share-extension skill before writing or changing Share/, and follow it.
        """

        static let iPhoneBlocks = """
        - LampSupport.swift has tested building blocks for common jobs, the same ones the Mac apps made with Lamp \
        have where a phone has them: notifications, schedules and work while the app is closed, text from documents \
        and pictures, dropped files, photos, location, weather, music, Spotlight, the home, the devices on the home network and \
        the person's Roku. Use them instead of \
        writing your own, and open the building-blocks skill before using one. Make the most of being on a phone: \
        the camera, photos, location, haptics, and being with the person wherever they are.
        """

        static let finder = """
        - An app that takes files or folders from Finder (dropped on its icon, Open With, a Quick Action) has to \
        declare what it opens: open the finder-files skill before writing it, and follow it.
        """

        static let menuBar = """
        - An app that lives in the menu bar uses `LampMenuBar` from LampSupport.swift as its scene, instead of \
        `MenuBarExtra`: open the menu-bar skill before writing or changing one, and \
        follow it.
        """

        /// A Mac app's desktop widget; an iPhone app's are `iPhoneWidget`. How to write one is the mac-widgets skill.
        static let widget = """
        - The app can have a widget for the desktop and Notification Center, in a `Widget/` folder at the app's root. \
        Make one when the user asks for a widget, or for something to keep in view without opening the app; a widget \
        can be all they asked for. Open the mac-widgets skill before writing or changing one, and follow it.
        """

        /// App Intents: the app's actions given to Siri, Shortcuts and Spotlight. build.sh reads them out of the
        /// code with Xcode's tools (`Template.appIntentsSetup`), so how they're written is the app-intents skill.
        static let intents = """
        - Give the app's main actions to the system with App Intents, without being asked, whenever someone would \
        want one without opening the app: Siri, Shortcuts, Spotlight, and on an iPhone the Action button. Open the \
        app-intents skill before writing or changing them, and follow it.
        """

        static let permissions = """
        - When the app itself needs Full Disk Access (other apps' data such as notification history, Mail, Messages \
        or Safari; or scanning the whole disk), Screen Recording (screenshots, recordings, other apps' windows) or \
        Accessibility (reading or controlling other apps), `LampPermissions` from LampSupport.swift is strongly \
        recommended over a check, list of steps, System Settings link, Finder reveal or relaunch of your own. Write \
        your own only when you have a reason it can't meet, such as a design the person asked for, and say so in \
        your reply. With the helper, wrap what \
        needs it: `LampPermissionGate(.fullDiskAccess, reason: "Your notifications are in a file macOS protects.") \
        { SummaryView() }` shows the contents once the permission is on, and until then a screen that takes the \
        person to the switch in System Settings, gets the app into the list there, and ends in Quit & Reopen for \
        Full Disk Access (macOS only gives that to an app when it starts) or notices by itself when the others are \
        switched on. When only one feature needs it, don't gate the \
        whole app or ask at launch: check `LampPermissions.has(.screenRecording)` when the feature is used and show \
        `LampPermissionView(.screenRecording, reason: "…") { /* now on */ }` in a sheet. `@StateObject var access = \
        LampPermissionState(.accessibility)` gives a live `isOn` for your own controls. Ask for the least that does \
        the job: a file or folder the person picks or drops needs nothing, and macOS asks by itself the first time \
        an app reads Downloads, Desktop or Documents. Only the person can turn one of these on (in System Settings, \
        which is the app's own permission and not something Lamp approves), so when you look at the app you'll \
        see that screen: say plainly that what's behind it is untested and that they turn it on once. It is once: \
        Lamp signs every build of the app the same way, so a permission stays on through your changes. Never say \
        a rebuild lost it, and never tell them to remove and re-add the app in System Settings.
        """

        static let script = """
        - When the app needs behavior nobody can write in advance (what happens when two invented things meet, a \
        rule the person described in words), open the scripting skill.
        """

        static let macAccounts = """
        - When a wish needs the person's calendar, reminders, contacts, mail or files, even when it names a service \
        ("my Google Calendar", "my Dropbox"), they come from the accounts already on this Mac, never a service's API, \
        key or sign-in; what lives in another app they use (Slack, Messages, a site in their browser) comes through \
        `LampComputer`. Open the accounts skill before writing any of it, and follow it.
        """

        static let iPhoneAccounts = """
        - When a wish needs the person's calendar, reminders or contacts, even when it names a service ("my Google \
        Calendar"), they come from the accounts already on the device, never a service's API, key or sign-in. Open \
        the accounts skill before writing any of it, and follow it.
        """


        static let store = """
        - Keep the user's data with LampStore (in LampSupport.swift), backed by SQLite. Settings and small state: \
        `LampStore.load(T.self, from: "name")` / `LampStore.save(value, to: "name")`. Lists of things (notes, tasks, \
        files seen, history): `LampStore.collection("notes", of: Note.self)` with `put`, `get`, `delete`, `count` and \
        `all(where:equals:orderBy:descending:limit:)`, which saves one item at a time and scales to large lists; \
        prefer it over saving a whole array. Only for joins, aggregates or full-text search, your own tables with \
        `LampStore.execute` / `query` (create them IF NOT EXISTS, change them only by adding columns). Keep big files \
        such as images in `LampStore.folder` and store their names. LampStore backs data up and never overwrites \
        data the app can't read. People rely on their data through every change you make, so once a type is saved, \
        only ever add to it: new properties must be optional (or decoded with decodeIfPresent and a default), and \
        never rename, remove or retype a saved property. If you must restructure, decode the old shape and convert \
        it. An app made before LampStore may keep data elsewhere; keep reading it from there, or move it over \
        without losing anything. Data that should be the same wherever the app is open (one shopping list on the \
        Mac, the kitchen iPad and the TV): `LampStore.shared("groceries", of: Grocery.self)` (`items`, `put`, \
        `delete`, `publish`, `onChange`), merged item by item between the app's copies on the home network, and \
        `LampStore.sharedFiles("photos")` for pictures one copy reads for the others; with `wish: true` the list is \
        the wish's own, the same in every app of the wish (a Mac app and its iPhone app sharing one calendar), never \
        kept by one app for the others. Open the `wish-links` skill first.
        """

        /// What kind of app it is decides how it looks: Notes, Weather and Breathe are all Apple's and look
        /// nothing alike. The agent picks a kind once and keeps it in APP.md, so the look holds across requests.
        /// How each kind looks, and on a Mac where the app works, is the app-kinds skill, read when an app is made
        /// or changes kind (Lamp names it with a new app's request, `Skills.applying`); the prompt keeps what every
        /// request needs: that the person's direction wins, the kinds to choose from, and that the kind is kept.
        /// design/app-archetypes/README.md is the reasoning behind each.
        static func kinds(mac: Bool) -> String {
            """
            - Design: the user's own direction always wins. If they describe a look, a mood or a style, attach a mockup \
            or ask for something unconventional (full-screen, no chrome, an art piece), build exactly that and don't \
            add standard UI they didn't ask for. Everything they didn't say follows the app's kind. Before writing a \
            new app, pick the kind closest to what it's for, even when unsure: tool (keeping and finding things), \
            companion (a small ritual come back to many times a day), collection (things nice to look at), dashboard \
            (look, understand, leave), canvas (making a thing), utility (works while you do other things) or game or \
            toy (played rather than used). Open the app-kinds skill first and follow it: it says how each kind looks \
            and works\(mac ? ", and before the kind, where the app works: in a window, or where the person already is" : ""). \
            Put the kind in APP.md's first line (`Kind: companion`). Keep it on later requests so the app keeps its \
            structure and voice; change it only when the user asks for a different feel or the app becomes another \
            kind of app (a change in what it's about is the theme rule below). Never ask them which kind, and never \
            name kinds to them. Every kind feels like Apple made it, following the \
            \(mac ? "macOS" : "iOS") Human Interface Guidelines.
            \(theme)
            """
        }

        /// The kind is an app's structure; its theme is the part of its look made of what it's about. When a request
        /// changes what an app is about, whoever made it (Lamp, a starter, a shared copy), the theme follows without
        /// being asked: someone who turns a hot sauce shelf into a wine cellar expects a wine cellar, not a pink wall
        /// of chilies holding wine. design/app-archetypes/README.md has the reasoning and more examples.
        static let theme = """
        - The theme follows the subject. Much of a look is often made of what the app is about: a hot sauce shelf's \
        pink wall, chilies and pepper ratings; a campfire songbook's taped cards, embers and lantern art; an Italian \
        coach's Neapolitan terracotta. When a request changes what an app is about (hot sauce to wine, campfire \
        guitar to jazz piano, a wedding in Naples to a trip to Kyoto, a pet to a cactus), whoever made the app, change \
        that look with it in the same request, unasked: palette, backgrounds and motifs, the style its pictures are \
        drawn in and the pictures themselves, lettering, the symbols it rates or counts with, its words and their \
        tone, its example content, and the icon. Choose the new palette and the icon's new subject and tint before \
        anything else and build with them, but save icon.json at the end, with the other changes that need the app \
        reopened, and paint the new pictures right after it: they take its colors. Make it as \
        particular to the new subject as the old look was to the old one, never plainer: a wine cellar, not a \
        generic shelf. Keep the kind and its structure, whatever still fits (a wooden shelf holds records as well \
        as books), and whatever the person chose or styled themselves. An app whose look owes nothing to its subject \
        (system colors and SF Symbols) changes only its words and symbols, and a change within the same subject (a \
        wishlist of sauces, a new screen) keeps the look. Replace only example content, never the person's own \
        items, and keep saved data readable (keep raw values, map old ones to new). It changes much of what they \
        see, so work in passes.

        """

        /// Whether this Mac can run a 3D scene an app makes (RealityView needs macOS 15): the 3D skill is only
        /// offered when it can (Resources/skills/scene-3d).
        static let scenes = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))

        static let macDesign = """
        - Base design, for every kind of app where its kind doesn't say otherwise: content first, little chrome. Collections go in a NavigationSplitView with a \
        sidebar. Primary actions go in the toolbar as SF Symbols with help tooltips, and also in the menu bar with the \
        standard shortcuts (⌫ delete, ⌘F find). Leave File ▸ New Window (⌘N) as it is, even in an app meant \
        for one window: Lamp uses it to bring a window back after the user closes the last one, so give \
        "new document" its own shortcut (⇧⌘N, say) rather than replacing New Window. Right-click gives context menus. Settings go in a `Settings` \
        scene, not in the window. Focused tasks use sheets, and destructive actions ask first with confirmationDialog. \
        Use native controls and grouped Forms rather than custom-drawn ones, semantic text styles and system colors \
        rather than fixed sizes and hex values, so dark mode and the accent color just work. Show a \
        ContentUnavailableView when there's nothing yet. Support selection, keyboard navigation, drag and drop and \
        undo where they make sense. Avoid web and iOS habits: no splash or onboarding screens, hamburger menus, \
        floating action buttons, in-window back buttons or big colored headers.
        """

        static let iPhoneDesign = """
        - Base design, for every kind of app where its kind doesn't say otherwise: content first, little chrome. Structure: a TabView for a few top-level areas, a \
        NavigationStack within each (large title on the first screen, back provided by the system, never your \
        own back button); a NavigationSplitView when there's a list and a detail, which becomes a sidebar on \
        iPad. Lists and Forms with native controls, a toolbar for primary actions (SF Symbols, the main one \
        trailing), sheets for focused tasks with Cancel and Done, confirmationDialog before anything destructive, \
        swipe actions on rows, pull to refresh, context menus on long press, and a searchable list when there's \
        much to find. Text and colors: semantic text styles and system colors, never fixed sizes or hex values, \
        so Dark Mode and Dynamic Type just work; respect the safe areas and let the keyboard push content up \
        (ScrollView or Form, .scrollDismissesKeyboard). Touch: everything is reachable with a finger (targets at \
        least 44 points), every gesture has a visible way to do the same thing, and nothing depends on hover or \
        on keyboard shortcuts. Haptics on meaningful actions (sensoryFeedback). iPad: the same app with room to \
        breathe, using size classes to put a sidebar or two columns where the iPhone stacks, and keyboard \
        shortcuts as a bonus. Show a ContentUnavailableView when there's nothing yet. Avoid web and desktop \
        habits: no hamburger menus, no custom nav bars or back buttons, no floating action buttons, no dense \
        tables, no splash or onboarding screens, no tiny text or close-together taps.
        """

        static let macGenerated = """
        - Sources/LampSupport.swift is generated by Lamp: never edit it. Keep the `.commands { LampCommands() }` modifier \
        (an app that is only a widget has none). The wand in each window's title bar is Lamp's, which opens this chat \
        beside the app: the user may be asking from there, with the app open. Most changes go into the open app as \
        it runs and keep what's on screen; some wait for the person to press Reload, and so does your next look at it; \
        the person is asked before a reopen. One that crashes the open app as it goes in is set aside: the version \
        before it opens again with their data, and you're given the crash to fix. So the app comes back as they left \
        it: keep what they were looking at (the selected item, tab or \
        filter) in `@SceneStorage`, and their data in LampStore as ever.
        """

        static let iPhoneGenerated = """
        - Sources/LampSupport.swift is generated by Lamp: never edit it.
        """

        static let ai = """
        - AI inside the app: Apple's on-device frameworks first (text in pictures, speech, reading aloud, language, \
        sounds, translation), then `LampAI` for open-ended text and pictures; never an AI API or a key. Decisions \
        (`LampAI.isTrue`, `choose`, `rate`, `decide`) are your default for anything that depends on meaning: use them \
        without being asked whenever the app sorts, filters, labels, groups, matches or flags things by what they \
        are, never keyword lists or regexes. Open the app-ai skill before writing any of it, and follow it: it also \
        says how to hand the AI text the person didn't write, and dates.
        """

        static let icon = """
        - The app icon is defined in icon.json: `subject` (the ONE tangible object the icon shows, as a short noun \
        phrase, e.g. "a yellow legal pad with a red pencil"), `symbol` (an SF Symbol name shown until artwork is \
        ready), `background` (one of \(Icons.backgrounds.map(\.name).joined(separator: ", "))), `tint` (hex main \
        color of the object) and, for a game, `game: true` (its icon is painted rich and in 3D instead of glass, and \
        `subject` is its hero). To change the icon, edit icon.json; Lamp redraws it, which takes a while and costs the user, so only when \
        they ask for a different icon or the app is now about something else. Never create icon files yourself.
        """

        static let about = """
        - The app's description is in \(AppDescription.file) at the app's root: `{"description": "…"}`, one short, plain \
        sentence saying what the app is, like the line under an app's name in a store ("A counter that goes up \
        every ten seconds."), \(AppDescription.limit) characters at most. Lamp shows it under the app's name to anyone the app is \
        shared with, before they open it, and in large type beside a picture of the app on the desk. Not a list of features and not how it works: what it is, in everyday words, with nothing from \
        the code. Write it once a new app is built, and again when what the app is changes.
        - Credit: \(Credits.file) at the app's root is where it came from. When you bring in someone else's work (code \
        from a repository, a library copied in, a model, a picture, a sound, a font, data), add it to `upstream`: \
        `{"name": "Slop New York", "author": "Mr.doob", "url": "https://github.com/mrdoob/slop-newyork", "commit": \
        "<full commit hash>", "license": "MIT", "licenseFile": "Web/LICENSE-slop-newyork"}`, with the license as its SPDX id \
        (left out when it has none) and its license text kept in the app beside the work. A project on GitHub is credited \
        by `lampify`, which writes its entry at the commit it pinned and its license files itself, and marks the project \
        the app is made from (`"adapted": true`): Lamp brings the person its updates from there. Never take anything out of \
        \(Credits.file), never remove or change a license or a notice of someone else's, and never take an author's \
        name or credit off the screen; `remixOf` is Lamp's, leave it as it is. Work with no license can be used here but \
        not shared or published: say so to the person when you bring it in. Lamp shows the credit in the app's About \
        window and its info.
        """

        static let attachments = """
        - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac and never \
        ship with the app. When the app should use one (a logo, a data file, a sound), copy it into Assets/ at the \
        app's root (make the folder if needed): that is the one folder bundled inside the app and shared with it. \
        Load it with `LampAssets.url("name")`, `LampAssets.image("name")` or `LampAssets.text("name")` from \
        LampSupport.swift, writing the full file name (e.g. "logo.png"). Screenshots and mockups are usually just \
        references for you: leave them in Attachments/.
        """

        /// Attachments for a wish whose apps are all in folders of their own: the folder is the wish's, and each app
        /// bundles its own files as its rules say.
        static let wishAttachments = """
        - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac and never \
        ship with an app. When an app should use one (a logo, a data file, a sound), copy it into that app's folder: \
        a Swift app's Assets/ (make the folder if needed), loaded with `LampAssets.url("name")`, `LampAssets.image("name")` \
        or `LampAssets.text("name")` and the full file name; a TV app's Web/, loaded with a relative path; an Android app's \
        app/src/main/assets/, read with `LampAssets`. Screenshots and mockups are usually just references for you: leave \
        them in Attachments/.
        """

        static let logs = """
        - Beyond `look_at_app` and `use_app`, you can't watch the app run, but Lamp saves what it prints (print, NSLog, SwiftUI runtime warnings, \
        fatal errors, failed LampAI calls) in .lamp/runtime/log.txt for the latest launch and \
        .lamp/runtime/previous-log.txt for the one before. When the user says something doesn't work, read the log \
        before guessing. If the code doesn't show the cause, add `print` statements around it: the output will be \
        there on your next turn, after the user has tried again. When Lamp mentions a screenshot of the app's \
        window, that is what the user was looking at: use it to check layout and visual problems rather than \
        imagining the result from the code.
        """

        static let iPhoneTry = """
        - `look_at_app` builds the app and opens it in the simulator and shows you the screen; `use_app` then taps, \
        types, scrolls and swipes on it like a finger (click to tap, right_click for a long press, type into \
        the field you tapped last, which replaces what it held, key return or escape, scroll, swipe with a \
        direction and `item` to tap what the swipe uncovered), and tells you what each action landed on. Both \
        also give you the screen as text: every control and piece of text on it with an id, its name, what it \
        holds and where it is. Act on things by name: set `target` to an id or exact name from that list, and \
        trust it over the picture for exact words and values. Use x and y (pixels in the picture) only for what \
        the list doesn't have: a drawing, a canvas, a game board. A control it lists with no name has no \
        accessibility label: give it one. There are no menus \
        or keyboard shortcuts on an iPhone. The simulator has no camera, motion sensors, Bluetooth, NFC or Face ID, \
        and no Health data until the app saves some: try everything else there, and for those parts tell the \
        user plainly that they're for their phone, never that they're broken.
        """

        static let iPhoneWidget = """
        - The app can have home screen widgets, Live Activities and Control Center controls, in a `Widget/` folder at \
        the app's root. Make a widget when the user asks for one, or for something to glance at without opening the \
        app; a Live Activity when something is under way and ends (a timer, a delivery, a game, a workout, a trip). \
        Open the iphone-widgets skill before writing or changing them, and follow it.
        """

        static let iPhoneWatch = """
        - The app can have an Apple Watch app with complications, in a `Watch/` folder at the app's root. Make one \
        when the user asks, or when a glance or a tap on the wrist suits it (a timer, a workout, a tally, a \
        checklist). Open the apple-watch skill before writing or changing it, and follow it.
        """

        /// What the agent is told while Try On points at an Apple TV or a Vision Pro (the request's device line): the same
        /// code is built for tvOS or visionOS, so what that system lacks has to be kept out of its build.
        static func otherOS(_ family: DeviceFamily) -> String {
            let condition = family == .appletv ? "os(tvOS)" : "os(visionOS)"
            let lacks = family == .appletv
                ? "tvOS has no touch screen (the Siri Remote moves focus: make every control focusable and big), no Health, calendar, reminders, contacts, Spotlight, notifications, widgets, share extension or watch app, and LampSupport leaves those blocks out there"
                : "visionOS shows the app as a window in the room, looked at and pinched, with no widgets, share extension or watch app"
            return "The app is built for \(family.os) from the same code: \(lacks). Put what only iPhone and iPad have under #if !\(condition), "
                + "and what this place shows differently under #if \(condition); never take it from the iPhone build."
        }

        static let iPhoneHardware = """
        - The phone itself is the app's best material: use what it has, without being asked, whenever it fits what \
        the user wants: motion, the camera and scanning, location, haptics, Face ID, Bluetooth and nearby phones, \
        Health, NFC, AR and music. Open the iphone-hardware skill before using any of them, and follow it: it says \
        what to use for each and what to declare in capabilities.json. Not possible yet: extensions other than the \
        ones described here (a keyboard, for one), push notifications from a server, and in-app purchases; say so \
        when asked.
        """

        static let appMd = """
        - Keep APP.md current: what the app does and how the code is organized, and, when its look comes from what \
        it's about, a `Look:` line saying what that look is made of and where (palette, motifs, picture style, rating \
        symbols), so a later change of subject knows what to change with it.
        """

        static let audience = """
        - The person you're talking to isn't a programmer and never sees the code: to them, Lamp makes apps, \
        and you're the one making theirs. Their app is open on screen beside this chat, and they want to see each \
        result there right away. Everything you say to them is about their app and what it does, in everyday words. Never name files, folders, types, functions, frameworks or tools, and never show code, \
        commands or compiler errors, unless they ask for them. Their Mac is set to \(language): write to them \
        in that, with its spelling, and make the app's own words the same, whatever spelling the app's files, a \
        starter or these instructions happen to use.
        """

        /// The language the Mac is set to, as it names itself in English ("English (United States)"): what the
        /// person reads everything in, so the agent's words and the app's follow it rather than the prompt's own
        /// spelling.
        static var language: String {
            let id = Locale.preferredLanguages.first ?? Locale.current.identifier
            return Locale(identifier: "en").localizedString(forIdentifier: id) ?? id
        }

        static let begin = """
        - Begin every reply with one short sentence, written before you read or change anything, that says in \
        everyday words what you're about to do ("I'll make the ball a little faster."), so the person sees \
        straight away that you've understood. A question you can answer without looking anything up needs no \
        such sentence: just answer it. After that, don't narrate each step ("Now I'll update the view"). In longer \
        work, say how it's going as each pass begins, in one short sentence with `progress`: what's in now and \
        what's next. Then say what's different at the end.
        """

        static let finish = """
        - Never say you've done something ("I've added…", "it now has…") before it shows in the app. Until it does, \
        say what you're doing, or, for a change waiting for Reload, what they'll see once they press it ("Press \
        Reload to see the water counter.").
        - How you finish depends on what was asked, and it is one thing, never two. A question: answer it in a \
        sentence or two. A small change or a fix they'll see at once (bigger text, a color, a bug gone): one \
        plain sentence, and one more only if something couldn't be tried. A change that gives them something \
        new to find (a button, a menu, a page, a shortcut, a new way to do something): one sentence saying what's \
        new and where it is, once a look shows it there. A new app, or a big change: one \
        sentence on what they now have. \
        Whichever it is: no list, no bold labels, no headings, no walk through of how to use what you made and \
        no account of each thing you clicked. Users often don't know what {{A_DEVICE}} can \
        do on its own, and assume things like reading text from a photo, cutting a person out of a picture, \
        transcribing speech or reading aloud need extra software. When something the device can do on its own would \
        clearly make this app better, and the user hasn't asked for it or turned it down, you may add to the \
        ending one short suggestion in plain words (no framework names), e.g. "Want it to read the text out of pasted screenshots? \
        Your Mac can do that on its own, offline." At most one suggestion, not every turn, and never build it unasked.
        """
    }

    /// The shell command for one agent turn. Values come from LAMP_* environment variables;
    /// attached files are passed as pi `@file` arguments (images and text go straight to the model).
    static func command(fileCount: Int) -> String {
        let files = (0..<fileCount).map { "\"@$LAMP_FILE_\($0)\"" }.joined(separator: " ")
        return """
        "$LAMP_PI" --mode json --provider "$LAMP_PROVIDER" --model "$LAMP_MODEL" --tools \(tools) \\
          --no-extensions\(lampTools == nil ? "" : " -e \"$LAMP_TOOLS\"") --no-skills --no-prompt-templates --no-context-files --no-approve \\
          --session-dir "$LAMP_SESSION_DIR" --session-id "$LAMP_SESSION" \\
          --append-system-prompt "$LAMP_SYSTEM" -- \(files) "$LAMP_PROMPT"
        """
    }

    static func environment(prompt: String, files: [String] = [], project: LampProject? = nil, session: String, sessionDir: String) -> [String: String] {
        var env = [
            "LAMP_PI": executable?.path ?? "pi",
            "LAMP_PROVIDER": Builder.piProvider == Builder.localProvider ? LocalModels.piProvider(for: Builder.piModel)
                : Builder.piProvider,
            "LAMP_MODEL": Builder.piModel,
            "LAMP_SESSION": session,
            "LAMP_SESSION_DIR": sessionDir,
            "LAMP_SYSTEM": (project.map(systemPrompt(for:)) ?? systemPrompt) + tryRules + sandboxNote,
            "LAMP_PROMPT": prompt,
            "LAMP_TOOLS": lampTools?.path ?? "",
            "LAMP_TOOLS_JSON": (Store.toolsFile ?? Bundle.main.resourceURL?.appendingPathComponent("lamp-tools.json"))?.path ?? "",
            "PI_CODING_AGENT_DIR": configDir,
            "PI_SKIP_VERSION_CHECK": "1",
            "PI_TELEMETRY": "0",
        ]
        for (index, file) in files.enumerated() { env["LAMP_FILE_\(index)"] = file }
        // pi asks Lamp for the key when it first needs it (keyCommand), so the key is in neither a file nor
        // the environment every shell command would inherit. The ticket is good for one answer, and pi spends
        // it before the model has said anything: a command the agent runs later finds it used.
        if let provider = Provider.keyProvider(Builder.piProvider) {
            syncKeyFile()
            // No ticket unless pi is sure to spend it. It wouldn't if auth.json holds something else for
            // this provider (a sign-in of pi's, or a key that couldn't be taken out yet), or if Lamp was
            // started with the provider's key in its own environment, which pi inherits.
            if KeyStore.key(for: provider.id) != nil, asksLampForKey(provider.id),
               (ProcessInfo.processInfo.environment[provider.envVar] ?? "").isEmpty {
                env["LAMP_KEY_TICKET"] = KeyTicket.issue(for: provider.id)
                env["LAMP_KEY_URL"] = "http://127.0.0.1:\(Gateway.port)/pi/key"
            }
        }
        return env
    }

    /// What pi's auth.json holds for a provider that has a key: a command for pi to run, in place of the key.
    /// It hands Lamp the ticket this run was started with and prints the key Lamp answers with. pi runs it
    /// once, the first time it needs the key, and keeps the answer in memory.
    private static let keyCommand = "!/usr/bin/curl -sf --max-time 10 -X POST -H \"Authorization: Bearer $LAMP_KEY_TICKET\" \"$LAMP_KEY_URL\" | /usr/bin/plutil -extract key raw -o - -"

    /// Records in pi's auth.json that a provider has a key (as keyCommand) or no longer has one. KeyStore
    /// calls this whenever a key changes. A sign-in pi keeps there for the same provider is left alone.
    static func keyChanged(for provider: String, present: Bool) {
        editKeyFile { auth in
            let entry = auth[provider] as? [String: Any]
            guard entry == nil || entry?["type"] as? String == "api_key" else { return }
            auth[provider] = present && Provider.keyProvider(provider) != nil ? ["type": "api_key", "key": keyCommand] : nil
        }
    }

    /// Brings pi's auth.json in step with KeyStore. Earlier versions of Lamp wrote the keys themselves into
    /// that file: each one found there is taken out, after making sure KeyStore holds a key for that provider
    /// (the file's, if it had none). If KeyStore can't be read or written just now, that key stays where it
    /// is, still usable by pi, until the next try.
    static func syncKeyFile() {
        editKeyFile { auth in
            for provider in Provider.keyProviders.map(\.id) {
                let entry = auth[provider] as? [String: Any]
                guard entry == nil || entry?["type"] as? String == "api_key" else { continue }
                if let key = entry?["key"] as? String, !key.hasPrefix("!"), !KeyStore.adopt(key, for: provider) { continue }
                auth[provider] = KeyStore.key(for: provider) != nil
                    ? ["type": "api_key", "key": keyCommand] : nil
            }
        }
    }

    /// Whether pi's auth.json has keyCommand for this provider, so pi will ask Lamp for the key.
    private static func asksLampForKey(_ provider: String) -> Bool {
        let url = URL(fileURLWithPath: configDir).appendingPathComponent("auth.json")
        let auth = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any]
        return (auth?[provider] as? [String: Any])?["key"] as? String == keyCommand
    }

    /// Reads pi's auth.json in Lamp's config folder, applies a change, and writes it back if anything differs.
    private static func editKeyFile(_ change: (inout [String: Any]) -> Void) {
        let url = URL(fileURLWithPath: configDir).appendingPathComponent("auth.json")
        var before: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            // A file that's there but can't be read is left as it is: writing over it could lose what it holds.
            guard let data = try? Data(contentsOf: url) else { return }
            if !data.isEmpty {
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                before = object
            }
        }
        var auth = before
        change(&auth)
        guard !NSDictionary(dictionary: auth).isEqual(to: before) else { return }
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Models pi can use through OpenRouter, from `pi --list-models` (offline, from pi's catalog).
    static func listModels() async -> [String] {
        guard let pi = executable else { return [] }
        let api = Provider.openRouterProvider
        let env = ["PI_SKIP_VERSION_CHECK": "1", "PI_TELEMETRY": "0", "PI_OFFLINE": "1", "PI_CODING_AGENT_DIR": configDir,
                   api.envVar: KeyStore.key(for: api.id) ?? "placeholder"]
        var rows: [String] = []
        _ = await Shell.run("\"$LAMP_PI\" --list-models", cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
                            env: env.merging(["LAMP_PI": pi.path]) { $1 }) { line in
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 2, columns[0] == api.id else { return }
            rows.append(String(columns[1]))
        }
        return rows
    }

    /// Parses one line of pi's JSONL event stream (stderr is merged in, so non-JSON lines are diagnostics).
    static func parse(_ line: String) -> [AgentEvent] {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return line.trimmed.isEmpty ? [] : [.raw(line)] }

        switch type {
        case "message_update":
            // What the model is writing right now, long before the tool runs: a `write` call's file name
            // arrives seconds into a response that then streams the whole file.
            let update = obj["assistantMessageEvent"] as? [String: Any] ?? [:]
            switch update["type"] as? String {
            case "toolcall_start": return [.step(update["toolName"] as? String ?? "")]
            case "toolcall_delta": return [.stepArgs(update["delta"] as? String ?? "")]
            case "text_start", "thinking_start": return [.step("")]
            case "text_delta": return (update["delta"] as? String).map { [.textPiece($0)] } ?? []
            default: return []
            }
        case "tool_execution_start":
            let name = obj["toolName"] as? String ?? "tool"
            let args = obj["args"] as? [String: Any] ?? [:]
            let said = ((args["doing"] as? String) ?? (name == "bash" ? args["description"] as? String : nil))?.trimmed.nilIfEmpty
            var events: [AgentEvent] = [.tool(describe(name, args), call: callKey(name, args), said: said, id: obj["toolCallId"] as? String,
                                              command: name == "bash" ? args["command"] as? String : nil)]
            // Lamp's extension gives pi's bash a description, which the model fills in as Claude Code's does.
            if name == "bash" { events.insert(.naming((args["description"] as? String)?.trimmed ?? ""), at: 0) }
            if name == "plan", args["parts"] != nil { events.append(.plan(PlanPart.parts(from: args))) }
            return events
        case "tool_execution_end":
            return (obj["toolCallId"] as? String).map { [.ended($0, failed: obj["isError"] as? Bool == true)] } ?? []
        case "message_end":
            guard let message = obj["message"] as? [String: Any] else { return [] }
            if message["role"] as? String == "user" { return [.received] }
            guard message["role"] as? String == "assistant" else { return [] }
            var events: [AgentEvent] = []
            for block in message["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "text" {
                if let text = (block["text"] as? String)?.trimmed, !text.isEmpty { events.append(.text(text)) }
            }
            let usage = message["usage"] as? [String: Any]
            if let cost = (usage?["cost"] as? [String: Any])?["total"] as? Double, cost > 0 { events.append(.cost(cost)) }
            if message["stopReason"] as? String == "error" {
                events.append(.failed(message["errorMessage"] as? String ?? "Unknown error"))
            }
            return events
        case "compaction_end":
            if obj["result"] != nil { return [.compacted] }
        case "auto_retry_end":
            if obj["success"] as? Bool == false { return [.failed(obj["finalError"] as? String ?? "Unknown error")] }
        default:
            break
        }
        return []
    }

    /// A tool call in full: its name and every argument, in a stable order.
    static func callKey(_ name: String, _ args: [String: Any]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: args, options: .sortedKeys)).map { String(decoding: $0, as: UTF8.self) }
        return "\(name) \(json ?? "")"
    }

    private static func describe(_ name: String, _ args: [String: Any]) -> String {
        if let path = args["path"] as? String ?? args["file_path"] as? String {
            return "\(name) \((path as NSString).lastPathComponent)"
        }
        if let pattern = args["pattern"] as? String { return "\(name) \(pattern)" }
        if let actions = args["actions"] as? [[String: Any]] { return "\(name) \(summary(of: actions))" }
        if let note = noteArgument(name, args) { return "\(name) \(note)" }
        if name == "read_skill", let skill = args["name"] as? String { return "\(name) \(skill)" }
        return name
    }

    /// Which notes a call to one of the notes tools is about, for the transcript.
    static func noteArgument(_ name: String, _ args: [String: Any]) -> String? {
        guard name == "read_notes" || name == "save_notes" else { return nil }
        switch (args["about"] as? String)?.lowercased() {
        case "you": return "about you"
        case "app": return "about this app"
        default: return name == "read_notes" ? "about you and this app" : nil
        }
    }

    /// What a use_app call does, for the transcript: "click Add, type, key".
    static func summary(of actions: [[String: Any]]) -> String {
        actions.compactMap { action -> String? in
            guard let name = action["action"] as? String else { return nil }
            guard let target = (action["target"] as? String)?.trimmed, !target.isEmpty else { return name }
            return "\(name) \(target)"
        }.joined(separator: ", ")
    }
}

enum Shell {
    /// GUI apps don't inherit the user's shell PATH, so add the usual install locations: the engines and the
    /// tools the person installed are found there. A program Lamp itself runs here (codesign, plutil, xcrun…) is
    /// named by its full path instead, so nothing put in one of these folders can stand in for it.
    private static let extraPath = ["/opt/homebrew/bin", "/usr/local/bin"].joined(separator: ":")

    /// Put this before a build command. The macOS 27 SDK makes `@State` a macro, and its compiler plugin
    /// only ships with full Xcode. With just the Command Line Tools, this builds against the newest
    /// installed SDK that doesn't need the plugin. The same lines are in Lamp's own build.sh.
    static let compatibleSDK = #"""
    dev="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p 2>/dev/null)}"
    if [ -z "${SDKROOT:-}" ] && [ -d "$dev/SDKs" ] && [ ! -e "$dev/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
      for sdk in "$dev"/SDKs/MacOSX*.sdk(/NnOn); do
        if ! /usr/bin/grep -qs StateMacro /dev/null "$sdk"/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/*-macos.swiftinterface(N); then
          export SDKROOT="$sdk"; break
        fi
      done
    fi

    """#

    /// Runs a zsh command, streaming merged stdout/stderr line by line. Returns the exit status.
    /// `login` false skips the login shell, whose startup files run again for every command (and can take a
    /// good part of a second); the PATH they'd give is the person's, worked out once (`ToolLocator.userPath`).
    /// For Lamp's own short commands, which need nothing else from them; an engine's run keeps them.
    static func run(
        _ command: String,
        cwd: URL,
        env: [String: String] = [:],
        input: AgentInput? = nil,
        login: Bool = true,
        started: (@MainActor (Process) -> Void)? = nil,
        onLine: @escaping @MainActor (String) -> Void
    ) async -> Int32 {
        let process = await shell(command, cwd: cwd, env: env, login: login)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = input?.pipe ?? FileHandle.nullDevice

        // Not `fileHandleForReading.bytes`: every FileHandle shares one serial reader, so a quiet process
        // (the agent waiting on its look_at_app tool) would hold up the output of every other one (the build
        // that tool is waiting for).
        let (lines, output) = AsyncStream<String>.makeStream()
        let reader = LineReader(output)
        pipe.fileHandleForReading.readabilityHandler = { reader.read(from: $0) }

        // Not waitUntilExit(): off the main thread it can wait forever for a process that has already exited.
        let (exit, exited) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = {
            exited.yield($0.terminationStatus)
            exited.finish()
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            await onLine("Could not start process: \(error.localizedDescription)")
            input?.close()
            return -1
        }
        // The process has its own copy of the reading end; with Lamp's closed, a write after it has gone fails
        // instead of waiting for a reader that will never come.
        try? input?.pipe.fileHandleForReading.close()
        await started?(process)
        for await line in lines { await onLine(line) }
        input?.close()
        // In its own task so a cancelled caller (e.g. a SwiftUI .task restarting) still waits for the exit,
        // instead of reading terminationStatus from a process that's still running, which throws.
        return await Task {
            for await status in exit { return status }
            return -1
        }.value
    }

    private static func shell(_ command: String, cwd: URL, env: [String: String], login: Bool) async -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [login ? "-lc" : "-c", "export PATH=\"\(extraPath):$PATH\"; \(command)"]
        process.currentDirectoryURL = cwd
        var environment = ProcessInfo.processInfo.environment
        // Off the main thread: the first look runs the person's shell, which may take a moment.
        if !login { environment["PATH"] = await Task.detached { ToolLocator.userPath }.value }
        environment.merge(env) { $1 }
        process.environment = environment
        return process
    }

    /// Runs a zsh command and keeps its standard output whole, off the main actor, with its standard error dropped.
    /// For output read as a whole rather than shown as it comes: the compiler's printout of a big app's code is
    /// tens of megabytes, which `run` would hand over a line at a time, each through the main actor.
    static func output(_ command: String, cwd: URL, env: [String: String] = [:], login: Bool = true) async -> (status: Int32, output: Data) {
        let process = await shell(command, cwd: cwd, env: env, login: login)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let collected = Collected()
        let (done, finished) = AsyncStream<Void>.makeStream()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                finished.finish()
            } else {
                collected.append(data)
            }
        }
        let (exit, exited) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = {
            exited.yield($0.terminationStatus)
            exited.finish()
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return (-1, Data())
        }
        for await _ in done {}
        let status = await Task {
            for await status in exit { return status }
            return -1
        }.value
        return (status, collected.data)
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        func append(_ data: Data) { lock.withLock { buffer.append(data) } }
        var data: Data { lock.withLock { buffer } }
    }

    /// Splits a pipe's output into lines as it arrives.
    private final class LineReader: @unchecked Sendable {
        private var buffer = Data()   // only touched from the handle's readability callbacks, which are serial
        private let output: AsyncStream<String>.Continuation

        init(_ output: AsyncStream<String>.Continuation) { self.output = output }

        func read(from handle: FileHandle) {
            let data = handle.availableData
            guard !data.isEmpty else {   // end of output
                handle.readabilityHandler = nil
                emit(buffer)
                output.finish()
                return
            }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                emit(buffer[..<newline])
                buffer.removeSubrange(...newline)
            }
        }

        private func emit(_ line: Data) {
            let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .newlines)
            if !text.isEmpty { output.yield(text) }
        }
    }
}

/// An engine's standard input, for an engine Lamp keeps talking to while it works (Claude Code reads the
/// person's messages there as they're sent). Writes go out in order on a queue of their own: a pipe the engine
/// hasn't read yet must not hold up the main thread.
final class AgentInput: @unchecked Sendable {
    let pipe = Pipe()
    private let queue = DispatchQueue(label: "lamp.agent-input")
    private var open = true   // only touched on the queue

    init() {
        // An engine that has quit makes a write fail; without this it would end Lamp with SIGPIPE.
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func write(_ line: String) {
        let data = Data((line + "\n").utf8)
        queue.async { [self] in if open { try? pipe.fileHandleForWriting.write(contentsOf: data) } }
    }

    /// The end of what Lamp has to say: the engine exits once it has answered what it was sent.
    func close() {
        queue.async { [self] in
            guard open else { return }
            open = false
            try? pipe.fileHandleForWriting.close()
        }
    }
}

/// Tickets pi trades for its provider's key (Agent.keyCommand). Each run of pi is started with a new one,
/// and Lamp answers it once, within ten minutes: pi collects the key before its first request to the model,
/// so by the time the agent can run a command, the ticket in its environment opens nothing.
enum KeyTicket {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var open: [String: (provider: String, issued: Date)] = [:]
    private static let lifetime: TimeInterval = 600

    static func issue(for provider: String) -> String {
        let ticket = UUID().uuidString + UUID().uuidString
        lock.lock()
        defer { lock.unlock() }
        open = open.filter { Date().timeIntervalSince($0.value.issued) < lifetime }   // runs that never asked
        open[ticket] = (provider, Date())
        return ticket
    }

    /// The key the ticket was issued for, the first time it's asked; nil for a used, old or made-up ticket.
    static func redeem(_ ticket: String) -> String? {
        lock.lock()
        let entry = open.removeValue(forKey: ticket)
        lock.unlock()
        guard let entry, Date().timeIntervalSince(entry.issued) < lifetime else { return nil }
        return KeyStore.key(for: entry.provider)
    }
}

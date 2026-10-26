import SwiftUI

/// Replace macOS's help-book command: Lamp's guide is part of the app and works offline.
struct LampHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Lamp Help") { openWindow(id: "help") }
                // macOS reserves ⇧⌘/ for the Help menu's search field.
                .keyboardShortcut("/", modifiers: .command)
            Divider()
            Button("Report a Bug…") { openWindow(id: "bug-report") }
        }
    }
}

struct LampHelpScene: Scene {
    var body: some Scene {
        Window("Lamp Help", id: "help") {
            LampHelpView()
        }
        .defaultSize(width: 780, height: 640)
    }
}

struct LampHelpView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var selection: HelpTopic? = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(topic.title).font(.largeTitle.bold())
                    ForEach(topic.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title).font(.title3.bold())
                            Text(LocalizedStringKey(section.text))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if topic == .troubleshooting {
                        Button("Report a Bug…") { openWindow(id: "bug-report") }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: 620, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(topic)
        }
        .frame(minWidth: 680, minHeight: 440)
    }

    private var topic: HelpTopic { selection ?? .gettingStarted }
}

private struct HelpSection: Identifiable {
    let title: String
    let text: String
    var id: String { title }
}

private enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, phoneApps, changingApps, versions, sharing, ai, troubleshooting, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .phoneApps: "iPhone and iPad Apps"
        case .changingApps: "Changing Your Apps"
        case .versions: "Versions & Undo"
        case .sharing: "Sharing Apps"
        case .ai: "AI & Privacy"
        case .troubleshooting: "Troubleshooting"
        case .shortcuts: "Keyboard Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted: "hammer"
        case .phoneApps: "iphone"
        case .changingApps: "bubble.left.and.bubble.right"
        case .versions: "clock.arrow.circlepath"
        case .sharing: "square.and.arrow.up"
        case .ai: "cpu"
        case .troubleshooting: "wrench.and.screwdriver"
        case .shortcuts: "keyboard"
        }
    }

    var sections: [HelpSection] {
        switch self {
        case .gettingStarted:
            [
                HelpSection(title: "Make a wish", text: "Say what would make your day easier or more fun, and Lamp makes it real: an app, something in your menu bar, a widget, a helper that works in the background, or an app for your iPhone or Apple Watch. Start with one small wish, then keep changing it in its chat."),
                HelpSection(title: "Finish setup", text: "The first time you open Lamp, it welcomes you and gets two things ready. If Apple's app-building tools are missing, it opens Apple's installer: click Install, then Agree. It usually takes 5–10 minutes, and you can carry on meanwhile. Then choose what makes your apps: your Claude or ChatGPT account, or Lamp's own, with an OpenRouter key, a model on this Mac or another provider. Then you're on your desk, where a few apps that come with Lamp are ready to use and to change into your own. You can change this later in Lamp → Settings (⌘,)."),
                HelpSection(title: "Make your first wish", text: "Type it in the box at the top of Lamp's window, in your own words: a chore to take off your hands, a habit to keep, a game to play. Press Return to send. Or click the round button beside the box and say it; click it again when you're done, check the words and press Return. Lamp asks a question first only when your answer would change what it makes: click an answer, or type your own. Otherwise it fills in the rest with good guesses, names it, designs its icon, makes it and opens it, and you change it as you use it."),
                HelpSection(title: "Not sure what to wish for", text: "Click Help Me Find One under the box. Lamp asks a few questions about your days, one card at a time, then writes a wish with you and puts it in the message box. Change anything you like, then send it."),
                HelpSection(title: "Use your wishes", text: "Your wishes are on Lamp's desk. Click one to use it. When it lives somewhere you might not look, like your menu bar, your desktop as a widget, or in the background, Lamp says where. Right-click a wish and choose Change… to go to its chat; the back button, or ⌘[, takes you back to the desk. Mac apps are installed in Applications → \(Edition.name) Apps in your home folder; to change one while you use it, click the wand at its top right or choose Customize with Lamp… (⇧⌘E) from its own menu, and its chat opens beside it. iPhone and iPad apps open in a simulator on your Mac, or on your own iPhone or iPad.")
            ]
        case .phoneApps:
            [
                HelpSection(title: "Make an app for both the Mac and the iPhone", text: "Say it's for your Mac and your iPhone when you ask for it, or later ask for it to work on your iPhone too: Lamp writes one app that runs on both, and the Try On menu in the toolbar says where it opens, this Mac, a simulator or your own phone. It needs Xcode with an Apple Account signed in, and the team chosen in Settings → Building: Apple signs the Mac copy for that team, which is what lets the two share things like iCloud later."),
                HelpSection(title: "Make an iPhone or iPad app", text: "Say it's for your iPhone or iPad when you ask for it, or later ask for it to be an iPhone app. Lamp makes one app that works on both; the Try On menu picks which one it opens in. It needs Xcode, Apple's app for making apps, which is free in the App Store. If Xcode or anything it needs is missing, Lamp says what to install when you send your first request. To check at any time, choose Check iPhone & iPad Setup… from the Try On menu in the toolbar."),
                HelpSection(title: "Try it on your Mac", text: "The app opens in a simulator: an iPhone or iPad on your Mac's screen. Use the Try On menu in the toolbar, or right-click the wish on Lamp's desk, to switch between iPhone and iPad. While building, Lamp looks at the simulator and taps, types and swipes in it to check its work. That needs Lamp to be allowed under System Settings → Privacy & Security → Accessibility; Lamp asks the first time."),
                HelpSection(title: "Put it on your iPhone or iPad", text: "This needs an Apple Account signed in to Xcode (Xcode → Settings → Accounts). A free account is enough: Apple then lets apps run on your own devices for about a week before they stop opening, and Lamp puts each app back before then by itself while it's open and can reach the phone. To have that happen without you, check “Keep apps on your phones opening” in Lamp → Settings → Building: Lamp then opens when you log in and keeps running with its window closed. A free account also takes up to three apps on a phone: before a fourth, Lamp asks which of its apps to take off it. A paid Apple Developer membership removes that limit, and an app that uses iCloud, NFC, Siri, Apple's weather or Time Sensitive notifications needs one: Lamp says so before it builds the app. A free account newly added to Xcode needs a certificate before Lamp can use it: in Xcode → Settings → Apple Accounts, choose its team, click Manage Certificates, then + and Apple Development. Plug your phone into your Mac and unlock it. In the Try On menu, choose Pair and accept Trust This Computer on the phone, then choose the phone. Click Use (the Play button) and Lamp builds the app, signs it with your account and puts it on the phone; every finished change goes there too. The first time, turn on Developer Mode on the phone when asked (Settings → Privacy & Security → Developer Mode). The Apple team used for signing is in Lamp → Settings → Building."),
                HelpSection(title: "AI away from your Mac", text: "On your phone, an app's AI goes through Lamp while the phone and your Mac are on the same Wi‑Fi network. Away from it, the app needs an OpenRouter key: Lamp gives the key to the app, which keeps it on the phone. Choose the models it uses in Settings → Apps. What an app spends this way doesn't show in Lamp."),
                HelpSection(title: "What isn't possible yet", text: "iPhone and iPad apps can't be shared yet. Away from your Mac, an app on your phone can't use your Mac's other apps. Lamp sees the app only in the simulator, not on your phone's screen.")
            ]
        case .changingApps:
            [
                HelpSection(title: "Ask for a change", text: "Right-click a wish on Lamp's desk, choose Change…, and describe the change in its chat. Be specific about what happens now and what you want instead. Lamp rebuilds the app and reopens it, keeping its data."),
                HelpSection(title: "Show what you mean", text: "Attach screenshots, documents or data with the paperclip, drag them onto the chat, or paste a copied image or file. Say what Lamp should use from each attachment."),
                HelpSection(title: "While Lamp is working", text: "You can keep typing. Messages you send wait until the current change is finished, then go out together; click the ✕ beside a waiting message to take it back. Click Stop, beside the Send button, to cancel the change in progress. Turn on Agent Details in the toolbar to see each step the agent takes."),
                HelpSection(title: "Change a message you already sent", text: "Click the pencil beside one of your messages in the chat: it is always there on your latest message, and appears on earlier ones when you point at them. The message moves into the message box, and it and everything after it step out of the chat. Change the words and send as usual. The app then goes back to how it was before that message and Lamp makes the change you asked for instead. The versions made in between are still listed under Versions. If you change your mind before sending, press Escape in the message box and the chat is back as it was."),
                HelpSection(title: "Use or quit a wish", text: "Click it on Lamp's desk, or click Use (the Play button) in the toolbar of its chat. While it's open, that button becomes Quit. You can also right-click it on the desk and choose Open or Quit, or Rebuild & Open to build it again from its code.")
            ]
        case .versions:
            [
                HelpSection(title: "Undo a change", text: "Click Undo Last Change in the toolbar to go back to the version before the last change. Click it again to step further back. The same button is under the latest change in the chat, when undoing it leaves what you saved in the app readable. If a change was stopped or failed to build, Undo discards that unfinished change first. The agent keeps its conversation and is told to reread the app before its next change."),
                HelpSection(title: "Keep a version you like", text: "Choose File → Name This Version… (⌘S) to give the current version a name you will recognize later."),
                HelpSection(title: "Try a variation", text: "Right-click the wish on Lamp's desk and choose Duplicate, or choose File → Duplicate. Lamp makes a copy called the same name with “copy” after it, with the same code, versions and icon on a different color, and builds it. Change the copy as you like: the original stays as it was. The copy starts with an empty chat and its own data."),
                HelpSection(title: "Return to an earlier version", text: "Click Versions in the toolbar to see earlier versions, name them and go back to one. You can also point at one of your requests in the chat and click the clock beside it to go back to before or after that change. Going back changes the app's code and keeps the data saved in the app. Later versions are kept, so you can undo it.")
            ]
        case .sharing:
            [
                HelpSection(title: "Send a wish", text: "Click Share Wish in the toolbar of its chat, or right-click it on Lamp's desk. Share… sends it with AirDrop, Messages or Mail. Copy Wish File (⇧⌘C) puts it on the clipboard, ready to paste into a message. Export… saves it as a file. The recipient needs Lamp to open it."),
                HelpSection(title: "Share a wish as a link", text: "Click Share Wish, then Share Link…. Lamp shows what the link will show: the wish's name, a line about it, its words and a picture of the app. Change any of them, leave the picture out, or take it again if it shows something of yours. Copy Link puts the link on lamp.dev and copies it. Only the idea goes: whoever opens the link makes their own version with Lamp, or downloads Lamp to make it. To change what the link shows, open Share Link… again and click Update Link; Stop Sharing takes it down."),
                HelpSection(title: "What is included", text: "A shared wish carries its code, its description, its icon and the attached files the app itself uses. Your chat, your keys, the data you saved in the app and its version history stay on your Mac. The recipient gets their own copy to use and change."),
                HelpSection(title: "Open a shared wish", text: "Double-click a shared wish file (its name ends in .lampapp), or choose File → Import Shared Wish… (⌘O). Before building anything, Lamp lists what the app can access and, when AI is set up, says what the app does, raises any concerns and rates the risk. Read it, then click Build & Open or Cancel. If Lamp isn't set up yet, it keeps the app and shows you this once setup is done. If you already have the app, you choose Update or Keep Both instead. Updating keeps your data, and Versions can take the app back to how it was. Keep Both adds the new one as a separate app. Lamp's check is a guide, not a guarantee: only open apps from people you trust.")
            ]
        case .ai:
            [
                HelpSection(title: "Choose what builds your apps", text: "Open Lamp → Settings (⌘,) → Building to choose the agent, and its provider and model. Lamp's built-in agent works with an OpenRouter key or a model running on this Mac. Claude and ChatGPT use your subscription: Lamp uses the copy already on your Mac, with its sign-in; if there isn't one, Lamp downloads its own and you sign in once. Add, replace and remove keys, and download models for this Mac, in Settings → AI Providers."),
                HelpSection(title: "AI inside your apps", text: "Settings → Apps chooses the models your apps use. Wish Info in the toolbar of a wish's chat shows what answers it. Without an OpenRouter key, the text AI in your apps goes through whatever builds your apps, and pictures are made by ChatGPT, with your sign-in, if you chose it; otherwise an app that wants a picture asks for a key. When an app wants AI that isn't set up, its chat shows a card with the ways to set it up (a key, a download, a sign-in); Settings → Apps shows what answers your apps' text, decisions and pictures, and how to set each up when nothing can. Letting apps use your other apps (also in Settings → Apps) needs an OpenRouter key. Apps reach AI through Lamp, and open it in the background if it is not running."),
                HelpSection(title: "Commands and files", text: "Settings → Building sets when Lamp asks before the agent runs a command (Only when risky, Always or Never) and whether Lamp's built-in agent or ChatGPT asks before opening files outside the app's folder. When a request appears above the message box, read it and choose Allow or Deny. Lower-risk requests also offer Allow All This Turn."),
                HelpSection(title: "Pictures and app output", text: "Settings → Building also controls whether the agent sees pictures of your apps' windows and what they print while running. Both help the agent find and fix problems, and both go to the AI model you chose. Turn them off for apps that show or print things you would rather keep to yourself."),
                HelpSection(title: "What Lamp remembers", text: "Lamp keeps short notes as you build: how you like things, which every new app starts out knowing, and for each app what you decided and what you turned down. They carry over when you switch the agent or model. When Lamp notes something, the chat shows what it noted, with Undo to take it back. The AI is told in a line what the notes cover and opens them only when a request needs them, so they add little to what a request costs. Settings → Memory lists them: click a set of notes to read, change or clear it, or turn off Remember how I like things to stop Lamp keeping notes. The notes stay on this Mac; a shared app does not include them."),
                HelpSection(title: "Usage counts", text: "While Lamp is in early testing, it tells the Lamp team how far people get through the welcome and whether new apps build and open the first time: which step was reached, the kind of app, which agent builds it, and how long it took. It never sends what you type, your apps' names or code, your files or your keys. The counts carry a random number made on this Mac, not your name or email.")
            ]
        case .troubleshooting:
            [
                HelpSection(title: "Report a bug", text: "Choose Help → Report a Bug… to describe what happened and review the diagnostics, then click Send to send the text shown to the Lamp team through lamp.dev. If sending fails or you are offline, copy or share it with the person who invited you. Lamp includes its version and build, your macOS version, the selected engine and activity labels. Log text, keys, chat and app code are left out unless you add them yourself. Nothing is sent automatically. New Report… starts a fresh snapshot after asking before replacing your draft."),
                HelpSection(title: "A build or change failed", text: "Read the message in the chat. When an app does not build, Lamp sends the compiler errors back to the agent, up to three times. If it still fails, describe what you wanted and ask Lamp to fix it, or click Undo Last Change. Agent Details in the toolbar shows more of what happened."),
                HelpSection(title: "Your key or sign-in does not work", text: "Double-click the provider in Settings → AI Providers to replace its key, and check that the account has credit or quota. For Claude or ChatGPT, Settings → Building shows whether it is signed in, with a Sign In… button if it is not. Claude needs a paid plan."),
                HelpSection(title: "A local model will not start", text: "Try a smaller model; it may need more memory than your Mac has. Double-click Native Mac AI in Settings → AI Providers to see how much memory each model needs and to download another."),
                HelpSection(title: "An app says it couldn't reach Lamp", text: "Open Lamp and try again. If the app still cannot reach Lamp, quit any extra copies of Lamp and reopen the one you want to use."),
                HelpSection(title: "Customize with Lamp opens the wrong copy", text: "You have more than one Lamp on this Mac. Open the copy you want once, or delete the copies you no longer use."),
                HelpSection(title: "App-building tools need attention", text: "If Apple's app-building tools are missing, for example after a macOS update, Lamp shows its Welcome screen and opens Apple's installer. Click Install, then Agree. If the installer does not appear, click Show Installer Again. If you use full Xcode and a build mentions its license, open Xcode and agree to the license.")
            ]
        case .shortcuts:
            [
                HelpSection(title: "In Lamp", text: "⌘N — New Wish\n⌘[ — Back to all your wishes\n⌘O — Import Shared Wish\n⌘S — Name This Version\n⇧⌘C — Copy Wish File\n⌘, — Settings\n⌘/ — Lamp Help\n⇧⌘/ — Search the Help menu\nEscape — Put back a message you took from the chat to change"),
                HelpSection(title: "In the chat", text: "Return — Send a message\nShift-Return — Add a new line\n⌘V — Paste text, or attach a copied image or file\nTab — Use the suggested next request\nEsc — Dismiss the suggestion"),
                HelpSection(title: "In an app built with Lamp", text: "⇧⌘E — Customize with Lamp")
            ]
        }
    }
}

import SwiftUI

/// Replace macOS's help-book command: Lamp's guide is part of the app and works offline.
struct LampHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Lamp Help") { openWindow(id: "help") }
                // macOS reserves ⇧⌘/ for the Help menu's search field.
                .keyboardShortcut("/", modifiers: .command)
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
    case gettingStarted, changingApps, versions, sharing, ai, troubleshooting, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
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
                HelpSection(title: "Make the app you need", text: "Describe a task and Lamp builds a real Mac app for it. Start with one small job, then keep improving the app in its chat."),
                HelpSection(title: "Finish setup", text: "The first time you open Lamp, it welcomes you and asks what your first app should do. Then it gets two things ready. If Apple's app-building tools are missing, it opens Apple's installer: click Install, then Agree. It usually takes 5–10 minutes, and you can carry on meanwhile. Then choose what makes your apps: your Claude or ChatGPT account, or Lamp's own, with an OpenRouter key, a model on this Mac or another provider. Your first app starts building as soon as everything is ready. You can change this later in Lamp → Settings (⌘,)."),
                HelpSection(title: "Build your first app", text: "Click New App at the bottom of the app list, or press ⌘N. Describe what the app should do: what you give it and what you want back. Or pick one of the starter ideas and change its request to suit you. Press Return to send. If the request is unclear, Lamp asks up to three short questions first. Then it names the app, designs its icon, builds it and opens it."),
                HelpSection(title: "Find your apps", text: "Your apps are listed in Lamp's sidebar and installed in Applications → \(Edition.name) Apps in your home folder. Double-click one in the sidebar to open it. In an app you built, choose Edit with Lamp… (⇧⌘E) from the app's own menu to return to its chat in Lamp.")
            ]
        case .changingApps:
            [
                HelpSection(title: "Ask for a change", text: "Select an app in the sidebar and describe the change in its chat. Be specific about what happens now and what you want instead. Lamp rebuilds the app and reopens it, keeping its data."),
                HelpSection(title: "Show what you mean", text: "Attach screenshots, documents or data with the paperclip, drag them onto the chat, or paste a copied image or file. Say what Lamp should use from each attachment."),
                HelpSection(title: "While Lamp is working", text: "You can keep typing. Messages you send wait until the current change is finished, then go out together; click the ✕ beside a waiting message to take it back. Click Stop, beside the Send button, to cancel the change in progress. Turn on Agent Details in the toolbar to see each step the agent takes."),
                HelpSection(title: "Change a message you already sent", text: "Click the circular arrow beside one of your messages in the chat: it is always there on your latest message, and appears on earlier ones when you point at them. The message moves into the message box, and it and everything after it step out of the chat. Change the words and send as usual. The app then goes back to how it was before that message and Lamp makes the change you asked for instead. The versions made in between are still listed under Versions. If you change your mind before sending, clear the message box and the chat is back as it was."),
                HelpSection(title: "Open or quit an app", text: "Click Open App (the Play button) in the toolbar. While the app is open, that button becomes Quit App. You can also right-click the app in the sidebar and choose Open or Quit, or Rebuild & Open to build it again from its code. Double-click an open app in the sidebar to bring it to the front.")
            ]
        case .versions:
            [
                HelpSection(title: "Undo a change", text: "Click Undo Last Change in the toolbar to go back to the version before the last change. Click it again to step further back. If a change was stopped or failed to build, Undo discards that unfinished change first. The agent keeps its conversation and is told to reread the app before its next change."),
                HelpSection(title: "Keep a version you like", text: "Choose File → Name This Version… (⌘S) to give the current version a name you will recognise later."),
                HelpSection(title: "Return to an earlier version", text: "Click Versions in the toolbar to see earlier versions, name them and go back to one. You can also point at one of your requests in the chat and click the clock beside it to go back to before or after that change. Going back changes the app's code and keeps the data saved in the app. Later versions are kept, so you can undo it.")
            ]
        case .sharing:
            [
                HelpSection(title: "Send an app", text: "Click Share App in the toolbar, or right-click the app in the sidebar. Share… sends it with AirDrop, Messages or Mail. Copy App File (⇧⌘C) puts it on the clipboard, ready to paste into a message. Export… saves it as a file. The recipient needs Lamp to open it."),
                HelpSection(title: "What is included", text: "A shared app carries its code, its description, its icon and the attached files the app itself uses. Your chat, your keys, the data you saved in the app and its version history stay on your Mac. The recipient gets their own copy to use and change."),
                HelpSection(title: "Open a shared app", text: "Double-click a shared app file (its name ends in .lampapp), or choose File → Import Shared App… (⌘O). Before building anything, Lamp lists what the app can access and, when AI is set up, says what the app does, raises any concerns and rates the risk. Read it, then click Build & Open or Cancel. Lamp's check is a guide, not a guarantee: only open apps from people you trust.")
            ]
        case .ai:
            [
                HelpSection(title: "Choose what builds your apps", text: "Open Lamp → Settings (⌘,) → Building to choose the agent, and its provider and model. Lamp's built-in agent works with an OpenRouter key (the easiest way to start), about twenty other providers, or a model running on this Mac. Claude Code and Codex use their own sign-in. Add, replace and remove keys, and download models for this Mac, in Settings → Providers."),
                HelpSection(title: "AI inside your apps", text: "Settings → Apps chooses the models your apps use. One app's own choices are in App Info in the toolbar. Without an OpenRouter key, the text AI in your apps goes through whatever builds your apps, and pictures are made by Codex, with your ChatGPT sign-in, if it is installed; otherwise an app that wants a picture asks for a key. Letting apps use your other apps (also in Settings → Apps) needs an OpenRouter key. Apps reach AI through Lamp, and open it in the background if it is not running."),
                HelpSection(title: "Commands and files", text: "Settings → Building sets when Lamp asks before the agent runs a command (Only when risky, Anything unusual, Always or Never) and whether Lamp's built-in agent or Codex asks before opening files outside the app's folder. When a request appears above the message box, read it and choose Allow or Deny. Lower-risk requests also offer Allow All This Turn."),
                HelpSection(title: "Pictures and app output", text: "Settings → Building also controls whether the agent sees pictures of your apps' windows and what they print while running. Both help the agent find and fix problems, and both go to the AI model you chose. Turn them off for apps that show or print things you would rather keep to yourself.")
            ]
        case .troubleshooting:
            [
                HelpSection(title: "A build or change failed", text: "Read the message in the chat. When an app does not build, Lamp sends the compiler errors back to the agent, up to three times. If it still fails, describe what you wanted and ask Lamp to fix it, or click Undo Last Change. Agent Details in the toolbar shows more of what happened."),
                HelpSection(title: "Your key or sign-in does not work", text: "Double-click the provider in Settings → Providers to replace its key, and check that the account has credit or quota. For Claude Code or Codex, Settings → Building shows whether it is installed and signed in, with a Sign In… button if it is not. It also helps to open the Claude or ChatGPT app and check that it works there."),
                HelpSection(title: "A local model will not start", text: "Try a smaller model; it may need more memory than your Mac has. Double-click Native Mac AI in Settings → Providers to see how much memory each model needs and to download another."),
                HelpSection(title: "An app says it couldn't reach Lamp", text: "Open Lamp and try again. If the app still cannot reach Lamp, quit any extra copies of Lamp and reopen the one you want to use."),
                HelpSection(title: "Edit with Lamp opens the wrong copy", text: "You have more than one Lamp on this Mac. Open the copy you want once, or delete the copies you no longer use."),
                HelpSection(title: "App-building tools need attention", text: "If Apple's app-building tools are missing, for example after a macOS update, Lamp shows its Welcome screen and opens Apple's installer. Click Install, then Agree. If the installer does not appear, click Show Installer Again. If you use full Xcode and a build mentions its license, open Xcode and agree to the license.")
            ]
        case .shortcuts:
            [
                HelpSection(title: "In Lamp", text: "⌘N — New App\n⌘O — Import Shared App\n⌘S — Name This Version\n⇧⌘C — Copy App File\n⌘, — Settings\n⌘/ — Lamp Help\n⇧⌘/ — Search the Help menu"),
                HelpSection(title: "In the chat", text: "Return — Send a message\nShift-Return — Add a new line\n⌘V — Paste text, or attach a copied image or file\nTab — Use the suggested next request\nEsc — Dismiss the suggestion"),
                HelpSection(title: "In an app built with Lamp", text: "⇧⌘E — Edit with Lamp")
            ]
        }
    }
}

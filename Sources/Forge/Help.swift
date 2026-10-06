import SwiftUI

/// Replace macOS's help-book command: Forge's guide is part of the app and works offline.
struct ForgeHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Forge Help") { openWindow(id: "help") }
                // macOS reserves ⇧⌘/ for the Help menu's search field.
                .keyboardShortcut("/", modifiers: .command)
        }
    }
}

struct ForgeHelpScene: Scene {
    var body: some Scene {
        Window("Forge Help", id: "help") {
            ForgeHelpView()
        }
        .defaultSize(width: 780, height: 640)
    }
}

struct ForgeHelpView: View {
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
                HelpSection(title: "Make the app you need", text: "Describe a task and Forge builds a real Mac app. Start with one small job, then keep improving it through the chat."),
                HelpSection(title: "Finish setup", text: "Forge checks for Apple's app-building tools on first launch. If an installer appears, choose Install and Agree; Forge carries on when it finishes. Add an OpenRouter key, or choose an AI provider, a local model, or a coding agent you already use. You can change these choices later in Forge → Settings (⌘,)."),
                HelpSection(title: "Build your first app", text: "Choose New App in the sidebar or press ⌘N. Describe what it should do, including what you put in and what you want back. You can also pick a starter idea and change its request. Press Return to send. Forge may ask a few questions before building, then opens the finished app."),
                HelpSection(title: "Find your apps", text: "Your apps appear in Forge's sidebar and in Applications → Forge Apps in your home folder. Double-click one in the sidebar to open it. In an app you built, press ⇧⌘E to return to its chat in Forge.")
            ]
        case .changingApps:
            [
                HelpSection(title: "Ask for a change", text: "Select an app in the sidebar and describe the change in its chat. Be specific about what happens now and what you want instead. Forge rebuilds and relaunches the app while keeping its data."),
                HelpSection(title: "Show what you mean", text: "Attach screenshots, documents or data with the paperclip, drag them onto the chat, or paste an image. Explain what Forge should use from each attachment."),
                HelpSection(title: "While Forge is working", text: "You can keep typing. Messages you send wait for the current change to finish; click the ✕ on a queued message to take it back. Use Stop to cancel the current turn. Turn on Agent Details in the toolbar to see what the agent is doing."),
                HelpSection(title: "Open or quit an app", text: "Use the Play button to open the app. While it is running, that button becomes Stop and quits it. You can also choose Quit from the app's right-click menu. Double-click an open app in the sidebar to bring it to the front.")
            ]
        case .versions:
            [
                HelpSection(title: "Undo a change", text: "Use Undo in the toolbar to go back to the version before the last change. If a change was stopped or failed to build, Undo discards that unfinished change first. The agent keeps the conversation and is told to reread the restored app before making another change."),
                HelpSection(title: "Keep a version you like", text: "Choose File → Name This Version… (⌘S) to give the current version a name you can recognise later."),
                HelpSection(title: "Return to an earlier version", text: "Open Versions in the toolbar to see earlier versions, name them and go back to one. Going back changes the app's code; your app's saved data is kept.")
            ]
        case .sharing:
            [
                HelpSection(title: "Send an app", text: "Click Share in the toolbar, or right-click the app and choose Share… to send it with AirDrop, Messages or Mail. Choose Export… to save a shared app file. The recipient needs Forge to open and build it."),
                HelpSection(title: "What is included", text: "Sharing includes the app's code, icon and attachments used by the app. Your chat, API keys, agent sessions and version history stay on your Mac. The recipient gets their own copy to use and change."),
                HelpSection(title: "Open a shared app", text: "Double-click a shared app file, or choose File → Import Shared App… (⌘O). Forge shows what the code can access and, when AI is set up, a review of possible concerns. Read the review before importing and only open apps from people you trust.")
            ]
        case .ai:
            [
                HelpSection(title: "Choose what builds your apps", text: "Open Forge → Settings (⌘,) → Building to choose the agent, provider and model. Settings → Providers manages API keys and models on this Mac. An OpenRouter key is the easiest way to get started; other providers and installed coding agents can use their own keys or sign-in."),
                HelpSection(title: "AI inside your apps", text: "Apps' text AI can use the provider or coding-agent sign-in you build with. Image generation uses an OpenRouter key when you have one; otherwise, it can use an installed Codex with your ChatGPT sign-in. Settings → Apps shows which option is available. Forge must be running for apps to reach its AI service."),
                HelpSection(title: "Commands and files", text: "Settings → Building controls when Forge asks before running commands and whether the built-in agent asks before accessing files outside the app's folder. When an approval card appears, review the request and choose Allow or Deny. Other coding agents follow their own file-access rules."),
                HelpSection(title: "Pictures and app output", text: "Settings → Building also controls whether the agent sees pictures of your apps and what they print while running. Both go to the AI model you chose. Turn them off for apps that show or print information you want to keep private.")
            ]
        case .troubleshooting:
            [
                HelpSection(title: "A build or change failed", text: "Read the error in the chat. Forge retries compiler errors automatically. If it still fails, describe what you were trying to do and ask it to fix the problem. Agent Details in the toolbar shows more of what happened."),
                HelpSection(title: "Your key or sign-in does not work", text: "Check the provider in Settings → Providers. Make sure the key is correct and the account has credit or quota. If you use Claude Code or Codex, check that it works in Terminal and that you are signed in."),
                HelpSection(title: "A local model will not start", text: "Try a smaller model; it may need more memory than your Mac has available. Check the model's setup in Settings → Providers → Native Mac AI."),
                HelpSection(title: "An app cannot reach Forge", text: "Open Forge and try again. If the app still says it cannot reach Forge, quit extra copies of Forge and reopen the one you want to use."),
                HelpSection(title: "Edit with Forge opens the wrong copy", text: "If you have more than one Forge installed, open the copy you want once and remove copies you no longer use."),
                HelpSection(title: "App-building tools need attention", text: "If macOS says the developer tools are missing, run xcode-select --install in Terminal. If you installed full Xcode and see a license error, open Xcode and accept its license.")
            ]
        case .shortcuts:
            [
                HelpSection(title: "In Forge", text: "⌘N — New App\n⌘O — Import Shared App\n⌘S — Name This Version\n⌘, — Settings\n⌘/ — Forge Help\n⇧⌘/ — Search the Help menu"),
                HelpSection(title: "In the chat", text: "Return — Send a message\nShift-Return — Add a new line\n⌘V — Paste text or an image"),
                HelpSection(title: "In an app built with Forge", text: "⇧⌘E — Edit with Forge")
            ]
        }
    }
}

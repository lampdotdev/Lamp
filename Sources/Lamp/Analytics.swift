import Foundation

/// Usage counts sent to PostHog while Lamp is alpha software, so the team can see where people get stuck:
/// how far the welcome gets, and whether a new app reaches its first run. There's no switch for it yet.
///
/// Each event is a name from `Event` with a few properties from fixed lists (a step, a kind of app, an
/// engine, an outcome). Never anything typed, a request, an app's name, a path or a key. Anonymous: the id is
/// made up on this Mac, and events make no person profile in PostHog. Help → AI & Privacy says what's sent.
///
/// Lamp Dev sends nothing, so working on Lamp doesn't count as using it. `LAMP_ANALYTICS_LOG=1` prints
/// what it would send.
enum Analytics {
    enum Event: String {
        // The welcome, in the order it's met.
        case welcomeStep = "onboarding_step_viewed"           // step
        case welcomeKind = "onboarding_kind_chosen"           // kind
        case welcomeMoreIdeas = "onboarding_ideas_shuffled"   // kind
        case welcomeIdeaPicked = "onboarding_idea_picked"     // kind, idea
        case welcomeDictation = "onboarding_dictation_started"
        case welcomeIdeaDone = "onboarding_idea_continued"    // kind, source, dictated
        case welcomeIdeaSkipped = "onboarding_idea_skipped"   // kind
        case welcomeToolsInstall = "onboarding_build_tools_install_requested"
        case welcomeToolsReady = "onboarding_build_tools_ready"   // already_installed
        case welcomeAgent = "onboarding_agent_chosen"         // agent, installed
        case welcomeAgentDownload = "onboarding_agent_download_clicked" // agent
        case welcomeSignIn = "onboarding_sign_in_started"     // agent
        case welcomeSignedIn = "onboarding_sign_in_finished"  // agent, success
        case welcomeKey = "onboarding_openrouter_key_checked" // valid
        case welcomeModelDownload = "onboarding_local_model_download_started"
        case welcomeDone = "onboarding_completed"             // agent, kind, has_idea, seconds

        // A new app, from New App to its first run.
        case appCreated = "app_created"                       // source
        case appFirstRequest = "app_first_request_sent"       // kind, has_attachments
        case appFirstRun = "app_first_run"                    // kind, seconds
        case appFirstFailed = "app_first_build_failed"        // kind, seconds, stopped
        case appFirstReplied = "app_first_reply_only"         // kind (the agent only asked questions)
    }

    /// The release's PostHog project. A project key only lets events in, so it belongs in the app.
    /// Empty: nothing is sent.
    static let projectKey = "phc_myM5viZtYmsj8K9kPJzzmh7uvSpUtGcjYiDVJyVYZUaN"
    static let endpoint = URL(string: "https://us.i.posthog.com/i/v0/e/")!

    private static var sends: Bool { !Edition.isDev && !projectKey.isEmpty }
    private static let logs = ProcessInfo.processInfo.environment["LAMP_ANALYTICS_LOG"] == "1"

    /// The same id every time on this Mac, made the first time something is counted.
    static var installID: String {
        let key = "analyticsID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    static func capture(_ event: Event, _ properties: [String: Any] = [:]) {
        guard sends || logs else { return }
        let body = payload(event, properties, id: installID, at: Date())
        if logs { NSLog("Analytics: %@ %@", event.rawValue, String(describing: properties)) }
        guard sends, let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        // Best effort: an event lost offline isn't worth keeping or retrying.
        session.dataTask(with: request).resume()
    }

    /// What's posted for one event: PostHog's capture shape, with what describes this Lamp and Mac added.
    static func payload(_ event: Event, _ properties: [String: Any], id: String, at date: Date) -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var all: [String: Any] = [
            "$process_person_profile": false,
            "$lib": "lamp-mac",
            "$os": "macOS",
            "$os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "$app_version": info["CFBundleShortVersionString"] as? String ?? "",
            "$app_build": info["CFBundleVersion"] as? String ?? "",
            "engine": Builder.engine.rawValue,
        ]
        all.merge(properties) { _, given in given }
        return ["api_key": projectKey, "event": event.rawValue, "distinct_id": id,
                "properties": all, "timestamp": ISO8601DateFormatter().string(from: date)]
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // MARK: Words for properties, from fixed lists

    static func kind(_ kind: AppKind) -> String {
        switch kind {
        case .mac: "mac"
        case .phone: "iphone"   // what the kind was called when it was iPhone or iPad, so the counts carry on
        case .universal: "universal"
        }
    }

    static func agent(_ choice: Builder.Choice) -> String {
        switch choice {
        case .claude: "claude"
        case .chatGPT: "chatgpt"
        case .openRouter: "openrouter"
        case .another: "another_provider"
        case .onThisMac: "on_this_mac"
        }
    }

    static func agent(_ engine: Engine) -> String { engine == .codex ? "chatgpt" : engine.rawValue }

    /// A built-in idea by its title; one made up on this Mac only as "invented", since its words came from a model.
    static func idea(_ idea: Idea, kind: AppKind) -> String {
        Ideas.pool(for: kind).contains { $0.title == idea.title } ? idea.title : "invented"
    }
}

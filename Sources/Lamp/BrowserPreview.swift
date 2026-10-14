import SwiftUI
import WebKit
import Network

/// The builder's way to try an app's sidebar without Chrome: Lamp draws the same surface the extension would,
/// from what the running app publishes, and acts as one more sidebar tab (`tab`), so `look_at_app` and `use_app`
/// with `sidebar` see it and press its buttons the way a person would. A button that reads the page gets the text
/// of a real page Lamp opens itself (`PageReader`), read by the extension's own capture script, so what the app is
/// handed here is what a click in Chrome hands it.
@MainActor
enum BrowserPreview {
    static let tab = "preview"
    /// The page beside each app's preview, and what the builder typed into its fields, by app.
    private static var pages: [String: PageReader.Page] = [:]
    private static var typed: [String: [String: String]] = [:]

    /// `look_at_app` with `sidebar`: the app is built and open already (Store.lookAtSidebar).
    static func look(_ project: LampProject, page address: String?) async -> (Int, [String: Any]) {
        var notes: [String] = []
        let declaration: BrowserCompanions.Declaration?
        switch BrowserCompanions.Declaration.read(project) {
        case .success(let value): declaration = value
        case .failure(let problem):
            declaration = nil
            notes.append(problem.message + " Without it the app isn't listed in Chrome's sidebar and Lamp's icon never lights up for it.")
        }
        if let address {
            switch await PageReader.read(address, selectors: declaration?.fits.compactMap(\.selector) ?? []) {
            case .success(let page):
                pages[project.id] = page
                notes.append("The page beside the sidebar is \(page.url) (\"\(page.title)\").")
            case .failure(let problem): notes.append(problem.message)
            }
        }
        if let page = pages[project.id], let declaration { notes.append(fitNote(declaration, page)) }
        guard await waitForSidebar(project) else {
            return (200, ["text": (notes + ["The app is open but its sidebar hasn't started. Call LampBrowser.start(surface:handle:) once when the app launches, from its shared model, not from a window."]).joined(separator: "\n\n")])
        }
        return await report(project, notes: notes, what: "The sidebar, drawn as Chrome shows it")
    }

    /// `use_app` with `sidebar`: clicks its buttons and types into its fields by target; nothing else applies.
    static func use(_ project: LampProject, actions: [[String: Any]], page address: String?, selection: String?) async -> (Int, [String: Any]) {
        var happened: [String] = []
        if let address, address != pages[project.id]?.url {
            let declaration = BrowserCompanions.Declaration.load(project)
            switch await PageReader.read(address, selectors: declaration?.fits.compactMap(\.selector) ?? []) {
            case .success(let page):
                pages[project.id] = page
                happened.append("Opened \(page.url) beside the sidebar (\"\(page.title)\").")
                if let declaration { happened.append(fitNote(declaration, page)) }
            case .failure(let problem): return (200, ["text": problem.message])
            }
        }
        guard await waitForSidebar(project) else {
            return (200, ["text": "The app's sidebar isn't running. Call look_at_app with sidebar first: it builds the app and opens it."])
        }
        let companions = BrowserCompanions.shared
        let printed = Runtime.logSize(project)
        for (index, action) in actions.enumerated() {
            let kind = action["action"] as? String ?? ""
            let number = "\(index + 1). \(kind)"
            guard let state = view(project) else { happened.append("\(number): the app's sidebar stopped."); break }
            if kind == "wait" {
                try? await Task.sleep(for: .seconds(min(action["amount"] as? Double ?? 1, 10)))
                happened.append("\(number): waited."); continue
            }
            guard let target = action["target"] as? String, !target.isEmpty else {
                happened.append("\(number): in the sidebar, name what to act on with `target` (an id or exact name from the sidebar as text)."); break
            }
            let ids = Ids(state.surface)
            if kind == "type" {
                guard let field = ids.field(target) else { happened.append("\(number): there's no field \"\(target)\" in the sidebar."); break }
                typed[project.id, default: [:]][field.id] = String((action["text"] as? String ?? "").prefix(4000))
                happened.append("\(number): typed into \"\(field.label)\"."); continue
            }
            guard kind == "click" else { happened.append("\(number): the sidebar only takes click, type and wait."); break }
            guard let button = ids.action(target) else { happened.append("\(number): there's no button \"\(target)\" in the sidebar."); break }
            if state.busy { happened.append("\(number): the sidebar is busy with an earlier click; its buttons are disabled. Wait, then try again."); break }
            var request: [String: Any] = ["op": "surface-action", "app": project.id, "id": UUID().uuidString, "revision": state.revision,
                                          "action": button.id, "fields": values(project, state.surface)]
            if button.readsPage || button.readsSelection == true {
                guard let page = pages[project.id] else {
                    happened.append("\(number): \"\(button.label)\" reads the page, so give use_app a `page`: the web address of a page it's for."); break
                }
                var text = page.text
                if button.readsSelection == true {
                    guard let chosen = selection?.trimmingCharacters(in: .whitespacesAndNewlines), !chosen.isEmpty else {
                        happened.append("\(number): \"\(button.label)\" reads a selection, so give use_app a `selection`: the passage of the page that's selected."); break
                    }
                    text = String(chosen.prefix(24000))
                }
                request["page"] = ["url": page.url, "title": page.title, "text": text, "scope": button.readsSelection == true ? "selection" : "page",
                                   "truncated": button.readsSelection == true ? false : page.truncated] as [String: Any]
            }
            let answer = companions.native(request, tab: tab, projects: Store.shared.projects)
            if let error = answer["error"] as? String { happened.append("\(number): the sidebar refused the click: \(error)"); break }
            typed[project.id] = nil   // sent with the click, as the extension sends what was typed
            // The app has a while to handle it (an AI answer can take a minute); then the sidebar settles.
            let id = request["id"] as! String, asked = Date()
            while !companions.isHandled(id, in: project), Date().timeIntervalSince(asked) < 150 { try? await Task.sleep(for: .milliseconds(250)) }
            if !companions.isHandled(id, in: project) { happened.append("\(number): clicked \"\(button.label)\"; the app hasn't finished handling it after two and a half minutes."); break }
            try? await Task.sleep(for: .milliseconds(1200))
            happened.append("\(number): clicked \"\(button.label)\"\(button.readsSelection == true ? ", with the selected passage" : request["page"] != nil ? ", with the page's text" : ""); the app handled it in \(Int(Date().timeIntervalSince(asked).rounded())) s.")
        }
        var text = "What happened:\n" + happened.joined(separator: "\n")
        if Runtime.sourcesChanged(project) {
            text += "\n\nThis is the app as last built: it doesn't have the changes you've made to the code since. Call look_at_app to build and open them."
        }
        var (status, result) = await report(project, notes: [], what: "The sidebar now")
        result["text"] = text + "\n\n" + (result["text"] as? String ?? "")
        if Privacy.sharesLog, let lines = Runtime.log(of: project, from: printed) { result["text"] = (result["text"] as! String) + "\n\nWhat the app printed meanwhile:\n\(lines)" }
        if !Privacy.sharesLog { result["text"] = (result["text"] as! String) + " " + Privacy.logOff }
        return (status, result)
    }

    private struct State { var surface: BrowserCompanions.Surface; var revision: String; var busy: Bool }
    private static func view(_ project: LampProject) -> State? {
        let answer = BrowserCompanions.shared.native(["op": "surface-view", "app": project.id], tab: tab, projects: Store.shared.projects)
        guard let raw = answer["surface"], let data = try? JSONSerialization.data(withJSONObject: raw),
              let surface = try? JSONDecoder().decode(BrowserCompanions.Surface.self, from: data) else { return nil }
        return State(surface: surface, revision: answer["revision"] as? String ?? "", busy: answer["busy"] as? Bool == true || surface.busy)
    }

    /// The app is running and publishing; the preview tab is then drawn for by the app within a beat.
    private static func waitForSidebar(_ project: LampProject) async -> Bool {
        let asked = Date()
        while Date().timeIntervalSince(asked) < 8 {
            if view(project) != nil {
                try? await Task.sleep(for: .milliseconds(800))
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private static func values(_ project: LampProject, _ surface: BrowserCompanions.Surface) -> [String: String] {
        Dictionary(uniqueKeysWithValues: surface.fields.map { ($0.id, typed[project.id]?[$0.id] ?? $0.value) })
    }

    private static func fitNote(_ declaration: BrowserCompanions.Declaration, _ page: PageReader.Page) -> String {
        guard let url = URL(string: page.url) else { return "" }
        let matching = declaration.fits.filter { $0.fitsAddress(url) && ($0.selector.map(page.present.contains) ?? true) }
        if let fit = matching.first {
            let how = [fit.site.map { "site \($0)" }, fit.path.map { "path \($0)" }, fit.selector.map { "selector \($0) is on the page" }].compactMap { $0 }
            return "This page fits browser.json (\(how.joined(separator: ", "))): Lamp's icon lights up on it in Chrome, and the sidebar opens on this app with \"\(declaration.offer)\"."
        }
        return "This page doesn't fit browser.json: Lamp's icon stays dim on it, and the person has to choose the app. " +
            "If the app is for pages like this, add a fit for it (a site, or a selector that's on pages like it and shown)."
    }

    /// The picture and the sidebar as text, with the notes before them.
    private static func report(_ project: LampProject, notes: [String], what: String) async -> (Int, [String: Any]) {
        guard let state = view(project) else { return (200, ["text": (notes + ["The app's sidebar stopped."]).joined(separator: "\n\n")]) }
        let declaration = BrowserCompanions.Declaration.load(project)
        let fits = pages[project.id].flatMap { page in declaration.map { d in URL(string: page.url).map { url in d.fits.contains { $0.fitsAddress(url) && ($0.selector.map(page.present.contains) ?? true) } } ?? false } } ?? false
        let shown = state.surface.fields.map { ($0.id, typed[project.id]?[$0.id] ?? $0.value) }
        var text = notes.joined(separator: "\n\n")
        guard Privacy.sharesPictures else { return (200, ["text": text + (text.isEmpty ? "" : "\n\n") + Privacy.picturesOff]) }
        text += (text.isEmpty ? "" : "\n\n") + Ids(state.surface).text(app: project.name, offer: fits ? declaration?.offer : nil,
                                                                         values: Dictionary(uniqueKeysWithValues: shown), busy: state.busy)
        let picture = Runtime.folder(project).appendingPathComponent("sidebar.png")
        let view = SidebarPicture(app: project.name, offer: fits ? declaration?.offer : nil, surface: state.surface,
                                  values: Dictionary(uniqueKeysWithValues: shown), busy: state.busy)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 360, height: nil)
        var screenshots: [String] = []
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]), (try? png.write(to: picture)) != nil {
            screenshots = Store.agentPictures([picture], in: project)
            text += "\n\n\(what) follows as a picture."
        }
        return (200, ["text": text, "screenshots": screenshots])
    }

    /// Ids for the sidebar's fields (f1…) and buttons (b1…), the way the screen as text names a window's.
    private struct Ids {
        let surface: BrowserCompanions.Surface
        init(_ surface: BrowserCompanions.Surface) { self.surface = surface }
        func field(_ target: String) -> BrowserCompanions.Surface.Field? {
            surface.fields.enumerated().first { "f\($0.offset + 1)" == target || $0.element.label == target || $0.element.id == target }?.element
        }
        func action(_ target: String) -> BrowserCompanions.Surface.Action? {
            surface.actions.enumerated().first { "b\($0.offset + 1)" == target || $0.element.label == target || $0.element.id == target }?.element
        }
        func text(app: String, offer: String?, values: [String: String], busy: Bool) -> String {
            var lines = ["The sidebar as text. Act on a field or button with `target` set to its id or exact name:", "app \"\(app)\""]
            if let offer { lines.append("offer \"\(offer)\" (shown because the page fits)") }
            lines.append("title \"\(surface.title)\"")
            if !surface.detail.isEmpty { lines.append("text \"\(surface.detail)\"") }
            for (i, field) in surface.fields.enumerated() {
                lines.append("f\(i + 1) field \"\(field.label)\"\((field.lines ?? 1) > 1 ? " (\(field.lines!) lines)" : "") = \"\(values[field.id] ?? field.value)\"")
            }
            for section in surface.sections {
                lines.append("section \"\(section.title)\"")
                if !section.text.isEmpty { lines.append("  text \"\(String(section.text.prefix(6000)))\"") }
                for item in section.items ?? [] { lines.append("  item \"\(item)\"") }
            }
            for (i, action) in surface.actions.enumerated() {
                let reads = action.readsPage ? " (reads the page)" : action.readsSelection == true ? " (reads the selection)" : ""
                lines.append("b\(i + 1) button \"\(action.label)\"\(reads)\(busy ? " disabled: busy" : "")")
            }
            return lines.joined(separator: "\n")
        }
    }
}

/// The sidebar as the extension draws it, for a picture: plain text and boxes, since ImageRenderer draws no controls.
private struct SidebarPicture: View {
    let app: String
    let offer: String?
    let surface: BrowserCompanions.Surface
    let values: [String: String]
    let busy: Bool
    private let green = Color(red: 0.24, green: 0.34, blue: 0.21)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app).font(.system(size: 15, weight: .semibold))
            if let offer { Text(offer).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(red: 0.7, green: 0.4, blue: 0.16)) }
            Text(surface.title).font(.system(size: 24, weight: .semibold, design: .serif)).padding(.top, 6)
            if !surface.detail.isEmpty { Text(surface.detail).foregroundStyle(.secondary) }
            ForEach(Array(surface.fields.enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.label)
                    Text((values[field.id] ?? field.value).isEmpty ? " " : values[field.id] ?? field.value)
                        .lineLimit((field.lines ?? 1) > 1 ? 12 : 1)
                        .frame(maxWidth: .infinity, minHeight: CGFloat(field.lines ?? 1) * 17, alignment: .topLeading)
                        .padding(7)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.73, green: 0.76, blue: 0.68)))
                }
            }
            ForEach(Array(surface.sections.enumerated()), id: \.offset) { _, section in
                Text(section.title.uppercased()).font(.system(size: 12, weight: .semibold)).foregroundStyle(green).padding(.top, 8)
                if !section.text.isEmpty { Text(String(section.text.prefix(1500))) }
                ForEach(Array((section.items ?? []).prefix(30).enumerated()), id: \.offset) { _, item in Text("•  " + item) }
            }
            Divider().padding(.top, 8)
            if surface.actions.contains(where: { $0.readsPage }) {
                Text("Using this page shares its text with \(app) and its AI.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(surface.actions.enumerated()), id: \.offset) { index, action in
                Text(action.label).font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 15).padding(.vertical, 9)
                    .foregroundStyle(index == 0 ? .white : green)
                    .background(RoundedRectangle(cornerRadius: 9).fill(index == 0 ? green : .white))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(index == 0 ? green : Color(red: 0.73, green: 0.76, blue: 0.68)))
                    .opacity(busy || surface.busy ? 0.55 : 1)
            }
        }
        .foregroundStyle(Color(red: 0.15, green: 0.16, blue: 0.13))
        .font(.system(size: 14))
        .padding(20)
        .frame(width: 360, alignment: .leading)
        .background(Color(red: 0.99, green: 0.99, blue: 0.97))
    }
}

/// Opens a web page out of sight and reads it with the extension's own capture script, for the preview. The page
/// is someone else's: the script runs in a world of its own, as Chrome runs the extension's, so the page's scripts
/// can't change what it reports; it connects only through `PublicOnlyProxy`, so neither the page, its redirects nor
/// anything it loads reaches this Mac or the local network, whatever a name says; and loading and reading each have
/// a time limit.
@MainActor
final class PageReader: NSObject, WKNavigationDelegate {
    struct Page { var url: String; var title: String; var text: String; var truncated: Bool; var present: Set<String> }
    private var finished: CheckedContinuation<Error?, Never>?
    private var refused: String?

    static func read(_ address: String, selectors: [String]) async -> Result<Page, BrowserCompanions.Problem> {
        guard let url = URL(string: address), isPublic(url) else {
            return .failure(.init("`page` must be the https address of a public web page."))
        }
        guard let script = try? String(contentsOf: BrowserSetup.source.appendingPathComponent("extension/surface-capture.js"), encoding: .utf8) else {
            return .failure(.init("This Lamp has no browser extension to read the page with."))
        }
        let reader = PageReader()
        return await reader.load(url, script: script, selectors: selectors)
    }

    /// https, and a name that could be on the internet: not this Mac, the local network or a bare IP address.
    /// Only a first sorting: where a name leads is checked where the connection is made (`PublicOnlyProxy`).
    static func isPublic(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              var host = url.host?.lowercased() else { return false }
        while host.hasSuffix(".") { host.removeLast() }
        guard host.contains("."), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), !host.hasSuffix(".internal") else { return false }
        let ip = host.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil || host.contains(":")
        return !ip && host != "localhost"
    }

    private func load(_ url: URL, script: String, selectors: [String]) async -> Result<Page, BrowserCompanions.Problem> {
        // A window that's never shown, so the page is laid out as on a screen and its hidden parts stay hidden.
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1280, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()   // no cookies kept: the preview is never signed in
        // Every connection goes through a proxy that refuses this Mac and the local network; without one, nothing is read.
        guard let proxy = try? PublicOnlyProxy(), let port = await proxy.start() else {
            return .failure(.init("Lamp couldn't read the page just now. Try again."))
        }
        defer { proxy.stop() }
        var route = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: port))
        route.allowFailover = false
        configuration.websiteDataStore.proxyConfigurations = [route]
        let web = WKWebView(frame: window.contentLayoutRect, configuration: configuration)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
        window.contentView = web
        web.navigationDelegate = self
        defer { web.stopLoading(); web.navigationDelegate = nil; window.contentView = nil; window.close() }
        web.load(URLRequest(url: url, timeoutInterval: 20))
        let failure = await wait(25)
        if let refused { return .failure(.init(refused)) }
        if failure != nil, let host = proxy.refused.first {
            return .failure(.init("Lamp didn't open \(url.absoluteString): \(host.prefix(200)) leads to this Mac or the local network, not a public web page."))
        }
        if let failure { return .failure(.init("Lamp couldn't open \(url.absoluteString): \(failure.localizedDescription)")) }
        try? await Task.sleep(for: .seconds(2))   // what the page draws after loading
        guard let landed = web.url, Self.isPublic(landed) else { return .failure(.init("\(url.absoluteString) went to an address that isn't a public https page.")) }
        let list = (try? JSONSerialization.data(withJSONObject: selectors)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        let call = script + "\n;JSON.stringify({page: (() => { try { return __lampCaptureSurface('page'); } catch (e) { return {error: String(e.message)}; } })(), " +
            "present: \(list).map(s => { try { return !!document.querySelector(s); } catch { return false; } })})"
        // In a world of the reader's own, and given ten seconds: a page that spins forever doesn't hold the builder up.
        let json: String? = await withCheckedContinuation { done in
            var answered = false
            func answer(_ value: String?) { if !answered { answered = true; done.resume(returning: value) } }
            web.evaluateJavaScript(call, in: nil, in: .defaultClient) { result in answer(try? result.get() as? String) }
            Task { try? await Task.sleep(for: .seconds(10)); answer(nil) }
        }
        guard let json, json.utf8.count < 400_000,
              let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let page = value["page"] as? [String: Any] else { return .failure(.init("Lamp opened \(url.absoluteString) but couldn't read it in time.")) }
        if let error = page["error"] as? String { return .failure(.init("Lamp couldn't read \(url.absoluteString): \(error.prefix(200))")) }
        let present = zip(selectors, value["present"] as? [Bool] ?? []).filter(\.1).map(\.0)
        return .success(Page(url: landed.absoluteString, title: String((page["title"] as? String ?? "").prefix(300)),
                             text: String((page["text"] as? String ?? "").prefix(24000)), truncated: page["truncated"] as? Bool ?? false,
                             present: Set(present)))
    }

    private func wait(_ seconds: Double) async -> Error? {
        await withCheckedContinuation { finished = $0
            Task { [weak self] in try? await Task.sleep(for: .seconds(seconds)); self?.finish(URLError(.timedOut)) }
        }
    }
    private func finish(_ error: Error?) {
        finished?.resume(returning: error)
        finished = nil
    }
    /// Every navigation, the first and any redirect or script's, has to be to a public https page.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, Self.isPublic(url) || url.absoluteString == "about:blank" else {
            if navigationAction.targetFrame?.isMainFrame != false {
                refused = "The page went to \(navigationAction.request.url?.absoluteString.prefix(200) ?? "another address"), which isn't a public https page, so Lamp stopped reading it."
                finish(nil)
            }
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
}

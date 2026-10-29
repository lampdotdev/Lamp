import Foundation

/// Where a shared page's requests go, worked out from its code rather than from words in it (`TVFiles.detected`): the
/// review says an app connects outside itself only when one of its requests goes to an outside address, and that it
/// may when a request's address can't be worked out. A request to the app's own files (its sounds, models, styles) is
/// the page reading itself, and a link is a website the person opens by clicking it.
///
/// It reads the page's JavaScript, HTML and CSS. In JavaScript it finds each place a request starts (fetch,
/// XMLHttpRequest, WebSockets, a picture's or script's address, an import, a 3D library's loader…) and works out the
/// address handed to it: from literals, joined strings and templates, variables and the values objects are given,
/// `new URL` with a base, and Lamp's own blocks for the web as lamp.js defines them. What it can't follow (a function's
/// parameter, a value read at run time, an address built from pieces) is unknown, never local. A web address written in
/// the code that no request or link it can follow uses is unknown too, since it may reach a request it can't see.
enum WebReach {
    struct Result: Equatable {
        /// Outside hosts the page's requests go to.
        var hosts: Set<String> = []
        /// A request to an outside address whose host the code builds as it runs.
        var unnamed = false
        /// A request whose address can't be worked out, or a web address the code holds that no followed request uses.
        var unknown = false
        /// Websites opened when the person clicks a link.
        var links = false
        /// Code loaded from outside the app (a script, module or worker).
        var remoteCode = false
        /// What the reading couldn't follow, for the reasons a request is unknown (tests and debugging).
        var why: [String] = []

        var connects: Bool { !hosts.isEmpty || unnamed }
    }

    /// Reads the page's files: its code (JavaScript, HTML, CSS, by name) and its data (glTF models may name outside
    /// files, which three.js would fetch).
    static func analyze(code: [(name: String, text: String)], data: [(name: String, data: Data)] = []) -> Result {
        var reader = Reader()
        for file in code {
            switch (file.name as NSString).pathExtension.lowercased() {
            case "js", "mjs", "ts", "tsx": reader.addScript(file.text, file: file.name)
            case "html", "htm": reader.addHTML(file.text, file: file.name)
            case "css": reader.addCSS(file.text, file: file.name)
            default: break
            }
        }
        for file in data {
            let ext = (file.name as NSString).pathExtension.lowercased()
            guard ext == "gltf" || ext == "glb", let json = gltfJSON(file.data, binary: ext == "glb") else { continue }
            reader.addModel(json, file: file.name)
        }
        return reader.finish()
    }

    // MARK: - Addresses

    /// Where a request to an address goes.
    enum Destination: Hashable {
        case local
        case external(String?)   // nil: an outside address whose host is built at run time
        case unknown
    }

    /// What's known of a string the code builds: all of it, how it starts, that it's the page's own address with
    /// anything after, or nothing.
    enum Shape: Hashable {
        case exact(String)
        case prefix(String)
        case page
        case any
    }

    static func destination(of shape: Shape) -> Destination {
        switch shape {
        case .exact(let text): destination(exact: text)
        case .prefix(let text): destination(prefix: text)
        case .page: .local
        case .any: .unknown
        }
    }

    /// A whole address: a web address is outside, data and the page's own files are not, any other scheme is unknown.
    static func destination(exact raw: String) -> Destination {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = webHost(text) { return host.isEmpty ? .external(nil) : .external(host) }
        let lower = text.lowercased()
        if lower.hasPrefix("data:") || lower.hasPrefix("blob:") || lower.hasPrefix("about:") || text.isEmpty
            || text.hasPrefix("#") || text.hasPrefix("?") { return .local }
        if scheme(of: text) != nil { return .unknown }
        // A bare host-less path: the app's own files (or, with no file there, nothing).
        return text.hasPrefix("\\") ? .unknown : .local
    }

    /// An address whose start is known: outside when the start names a web address, the app's own when the start is a
    /// path that whatever follows can't turn into another scheme or host, unknown otherwise.
    static func destination(prefix raw: String) -> Destination {
        let text = String(raw.drop { $0 == " " || $0 == "\t" || $0 == "\n" })
        let lower = text.lowercased()
        for web in ["http://", "https://", "ws://", "wss://"] where lower.hasPrefix(web) {
            let rest = text.dropFirst(web.count)
            // The host is settled once something ends it.
            guard let end = rest.firstIndex(where: { "/?#".contains($0) }) else { return .external(nil) }
            let host = hostName(String(rest[..<end]))
            return .external(host.isEmpty ? nil : host)
        }
        if lower.hasPrefix("data:") || lower.hasPrefix("blob:") || text.hasPrefix("#") || text.hasPrefix("?") { return .local }
        if text.hasPrefix("//") || text.hasPrefix("\\") { return .unknown }
        if text.hasPrefix("/") { return text.count >= 2 && !"/\\".contains(text[text.index(after: text.startIndex)]) ? .local : .unknown }
        // A relative path: settled once a / ? or # comes before any colon could make it a scheme.
        if let end = text.firstIndex(where: { "/?#".contains($0) }), !text[..<end].contains(":") { return .local }
        return .unknown
    }

    /// The host of a web address ("" when it's one with no host yet), or nil when it isn't one.
    private static func webHost(_ text: String) -> String? {
        let lower = text.lowercased()
        for web in ["http://", "https://", "ws://", "wss://", "//"] where lower.hasPrefix(web) {
            let rest = text.dropFirst(web.count)
            let end = rest.firstIndex { "/?#".contains($0) } ?? rest.endIndex
            return hostName(String(rest[..<end]))
        }
        return nil
    }

    private static func hostName(_ authority: String) -> String {
        var host = authority
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        if let colon = host.lastIndex(of: ":"), !host.hasSuffix("]") { host = String(host[..<colon]) }
        return host.lowercased()
    }

    private static func scheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let name = text[..<colon]
        guard let first = name.first, first.isLetter, name.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) else { return nil }
        return String(name).lowercased()
    }

    /// A host as people know it: its registered name ("open-meteo.com" for "api.open-meteo.com").
    static func site(_ host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2, labels.allSatisfy({ !$0.isEmpty }), !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return host }
        let second = labels[labels.count - 2]
        let keep = labels.last!.count == 2 && ["co", "com", "org", "net", "gov", "ac", "edu"].contains(second) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    // MARK: - glTF

    /// The JSON of a .gltf, or of a .glb's first chunk, which names the model's files by `uri`.
    private static func gltfJSON(_ data: Data, binary: Bool) -> Any? {
        guard binary else { return try? JSONSerialization.jsonObject(with: data) }
        let bytes = [UInt8](data)
        func word(_ at: Int) -> Int { at + 4 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 : -1 }
        guard bytes.count >= 20, word(0) == 0x46546C67, word(16) == 0x4E4F534A else { return nil }
        let length = word(12)
        guard length > 0, 20 + length <= bytes.count else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(bytes[20..<(20 + length)]))
    }
}

// MARK: - The reading

private struct Token {
    enum Kind { case ident, string, template, number, punct, regex }
    let kind: Kind
    let text: String
    /// A string's value, decoded.
    var value = ""
    /// A template's text between its `${…}`s, and what's inside each.
    var parts: [String] = []
    var holes: [[Token]] = []
    var newline = false
    var id = 0
}

/// A request found in the code: what it asks for, and whether it's a link the person clicks or code that runs.
private enum Use { case load, code, link }

private struct Reader {
    var scripts: [[Token]] = []
    /// What each name is given (`var url = …`, `url = …`), and the names nothing can tell (parameters, loop variables).
    var bindings: [String: [ArraySlice<Token>]] = [:]
    var appends: Set<String> = []
    var opaque: Set<String> = []
    /// What each property name is given in object literals and assignments, and values given under names that can't
    /// be told (`obj[key] = …`, `{...rest}`), which any property may be.
    var properties: [String: [ArraySlice<Token>]] = [:]
    var wild: [ArraySlice<Token>] = []
    var wildAny = false
    /// Import maps from the page's HTML: bare module names and where they lead.
    var imports: [String: String] = [:]
    /// Names of Lamp's blocks for the web that the page's own code gives a value, so they can't be read as Lamp's.
    var redefined: Set<String> = []
    var result = WebReach.Result()
    /// Web addresses written in the code, and those a request or link that was followed reads.
    var literals: [(text: String, file: String)] = []
    var touched: Set<String> = []
    /// Functions that make an element of a tag they're given and set each of an object's properties on it as an
    /// attribute (`el('a', { href: … })`): by name, which parameter is the tag and which the attributes.
    var builders: [String: (tag: Int, attributes: Int)] = [:]
    var builderBodies: [Int: [Range<Int>]] = [:]
    var createsLoaders = false
    var nextID = 0

    // MARK: Files

    mutating func addScript(_ text: String, file: String) {
        var lexer = Lexer(text: text, nextID: nextID)
        let tokens = lexer.tokens()
        nextID = lexer.nextID
        scripts.append(tokens)
        collectLiterals(tokens, file: file)
    }

    mutating func addHTML(_ text: String, file: String) {
        for element in HTML.elements(text) {
            let tag = element.tag
            if tag == "script" {
                let type = element.attributes["type"]?.lowercased() ?? ""
                if type == "importmap" {
                    if let json = try? JSONSerialization.jsonObject(with: Data(element.body.utf8)) as? [String: Any],
                       let map = json["imports"] as? [String: String] {
                        imports.merge(map) { $1 }
                    }
                } else if element.attributes["src"] == nil, type.isEmpty || type.contains("javascript") || type == "module" {
                    addScript(element.body, file: file)
                }
            }
            if tag == "style" { addCSS(element.body, file: file) }
            for (name, value) in element.attributes {
                if name.hasPrefix("on") { addScript(value, file: file) }
                if name == "style" { addCSS(value, file: file) }
            }
            if tag == "meta", element.attributes["http-equiv"]?.lowercased() == "refresh",
               let content = element.attributes["content"], let range = content.range(of: "url=", options: .caseInsensitive) {
                request(.exact(String(content[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " '\""))), .load, at: "\(file): refresh")
            }
            for (attribute, use) in HTML.urlAttributes(tag: tag, attributes: element.attributes) {
                guard let value = element.attributes[attribute] else { continue }
                let addresses = attribute == "srcset" ? HTML.srcset(value) : [value]
                for address in addresses {
                    request(.exact(address), use, at: "\(file): <\(tag) \(attribute)>")
                    if tag == "base", attribute == "href", case .external = WebReach.destination(exact: address) {
                        // Every relative address on the page then goes there.
                        request(.exact(address), .load, at: "\(file): <base>")
                    }
                }
            }
        }
    }

    mutating func addCSS(_ text: String, file: String) {
        for shape in CSS.addresses(text) { request(shape, .load, at: "\(file): CSS") }
    }

    mutating func addModel(_ json: Any, file: String) {
        func walk(_ value: Any) {
            if let object = value as? [String: Any] {
                for (key, item) in object {
                    if key == "uri", let uri = item as? String { request(.exact(uri), .load, at: "\(file): model file") }
                    else { walk(item) }
                }
            } else if let list = value as? [Any] {
                list.forEach(walk)
            }
        }
        walk(json)
    }

    /// Strings in the code that hold HTML or CSS (what goes into innerHTML, a style, a document.write) are read as
    /// such, a template's `${…}` standing for what can't be told; web addresses written in the code are kept to account
    /// for at the end.
    mutating func collectLiterals(_ tokens: [Token], file: String) {
        for token in tokens {
            switch token.kind {
            case .string:
                fragments(token.value, file: file, joined: true)
                if case .external = WebReach.destination(exact: token.value) { literals.append((token.value, file)) }
            case .template:
                fragments(token.parts.joined(separator: HTML.hole), file: file)
                if let first = token.parts.first, case .external = WebReach.destination(prefix: first) { literals.append((first, file)) }
                token.holes.forEach { collectLiterals($0, file: file) }
            default: break
            }
        }
    }

    mutating func fragments(_ text: String, file: String, joined: Bool = false) {
        if text.contains("<"), text.contains(">") || text.contains(HTML.hole) || text.contains("=") {
            for element in HTML.elements(text) {
                for (attribute, use) in HTML.urlAttributes(tag: element.tag, attributes: element.attributes) {
                    guard let value = element.attributes[attribute] else { continue }
                    // A plain string joined to what follows: `joinedMarkup` reads the value with it.
                    if joined, value.hasSuffix(HTML.open) { continue }
                    for address in attribute == "srcset" ? HTML.srcset(value) : [value] {
                        request(HTML.shape(address), use, at: "\(file): markup in a string")
                    }
                }
                if let style = element.attributes["style"] { CSS.addresses(style).forEach { request($0, .load, at: "\(file): style in a string") } }
            }
        }
        if text.contains("url(") || text.contains("@import") || text.contains("image-set(") {
            CSS.addresses(text).forEach { request($0, .load, at: "\(file): CSS in a string") }
        }
        // Accounted for here: an address written inside markup or a style is read as one.
        for address in HTML.addressesInMarkup(text) { touched.insert(address) }
    }

    // MARK: Requests

    mutating func request(_ shape: WebReach.Shape, _ use: Use, at place: String) {
        if case .exact(let text) = shape { touched.insert(text) }
        if case .prefix(let text) = shape { touched.insert(text) }
        let destination = WebReach.destination(of: shape)
        switch use {
        case .link:
            if destination != .local { result.links = true }
        case .load, .code:
            switch destination {
            case .local: break
            case .external(let host):
                if let host { result.hosts.insert(host) } else { result.unnamed = true }
                if use == .code { result.remoteCode = true }
            case .unknown:
                result.unknown = true
                result.why.append(place)
            }
        }
    }

    mutating func request(_ shapes: [WebReach.Shape], _ use: Use, at place: String) {
        for shape in shapes { request(shape, use, at: place) }
    }

    // MARK: The whole page

    mutating func finish() -> WebReach.Result {
        for tokens in scripts { collectBindings(tokens) }
        for (index, tokens) in scripts.enumerated() { findBuilders(tokens, script: index) }
        for (index, tokens) in scripts.enumerated() { findRequests(tokens, script: index) }
        for literal in literals where !touched.contains(literal.text) {
            result.unknown = true
            result.why.append("\(literal.file): \(literal.text) isn't read by a request it can follow")
        }
        return result
    }

    static let lampBlocks: Set<String> = ["LampAssets", "LampStore", "LampAI", "LampQuestion", "LampNative"]

    mutating func collectBindings(_ tokens: [Token]) {
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            let previous = i > 0 ? tokens[i - 1] : nil
            if token.kind == .ident, ["var", "let", "const"].contains(token.text) {
                // The names it declares; what they're given is read as the loop goes on, objects in it among them.
                _ = declarations(tokens, from: i + 1)
            }
            if token.kind == .ident, token.text == "function" || token.text == "catch" {
                // Its parameters: whatever any call passes.
                var j = i + 1
                if j < tokens.count, tokens[j].kind == .ident { j += 1 }
                if j < tokens.count, tokens[j].text == "(" { markOpaque(tokens[(j + 1)..<Syntax.matching(tokens, j)]) }
            }
            if token.text == "=>" {
                if let previous, previous.kind == .ident { opaque.insert(previous.text) }
                else if previous?.text == ")", let open = Syntax.opening(tokens, i - 1) { markOpaque(tokens[(open + 1)..<(i - 1)]) }
            }
            // A method in an object or class: name(params) {
            if token.text == "(", let previous, previous.kind == .ident,
               !["if", "for", "while", "switch", "catch", "function", "with"].contains(previous.text) {
                let close = Syntax.matching(tokens, i)
                if close + 1 < tokens.count, tokens[close + 1].text == "{", i >= 2, [",", "{", "}", ";", "static", "async", "get", "set"].contains(tokens[i - 2].text) || tokens[i - 2].newline {
                    markOpaque(tokens[(i + 1)..<close])
                }
            }
            if token.kind == .ident, previous?.text != ".", i + 1 < tokens.count {
                let next = tokens[i + 1].text
                if next == "=" || next == "+=" || next == "||=" || next == "??=" {
                    let end = Syntax.expressionEnd(tokens, from: i + 2)
                    if next == "+=" { appends.insert(token.text) }
                    bindings[token.text, default: []].append(tokens[(i + 2)..<end])
                    if Self.lampBlocks.contains(token.text) { redefined.insert(token.text) }
                } else if ["-=", "*=", "/=", "%=", "<<=", ">>=", "&=", "|=", "^=", "&&=", "++", "--"].contains(next) {
                    opaque.insert(token.text)
                }
            }
            // obj.name = …, and obj[key] = …
            if token.kind == .ident, previous?.text == ".", i + 1 < tokens.count, tokens[i + 1].text == "=" {
                let end = Syntax.expressionEnd(tokens, from: i + 2)
                properties[token.text, default: []].append(tokens[(i + 2)..<end])
                if i >= 2, Self.lampBlocks.contains(tokens[i - 2].text) { redefined.insert(tokens[i - 2].text) }
            }
            if token.text == "]", i + 1 < tokens.count, tokens[i + 1].text == "=" {
                let end = Syntax.expressionEnd(tokens, from: i + 2)
                wild.append(tokens[(i + 2)..<end])
            }
            if token.text == "{", Syntax.isObjectLiteral(tokens, at: i) { objectLiteral(tokens, at: i) }
            if token.kind == .ident, token.text == "in" || token.text == "of", let previous, previous.kind == .ident { opaque.insert(previous.text) }
            if token.kind == .ident, token.text == "new", i + 1 < tokens.count, tokens[i + 1].kind == .ident {
                var j = i + 1
                while j + 2 < tokens.count, tokens[j + 1].text == "." { j += 2 }
                if tokens[j].text.hasSuffix("Loader") { createsLoaders = true }
            }
            i += 1
        }
    }

    /// `a = …, b = …` after var, let or const, with destructured names unknown.
    mutating func declarations(_ tokens: [Token], from start: Int) -> Int {
        var i = start
        while i < tokens.count {
            if tokens[i].text == "{" || tokens[i].text == "[" {
                let close = Syntax.matching(tokens, i)
                markOpaque(tokens[(i + 1)..<close])
                i = close + 1
            } else if tokens[i].kind == .ident {
                let name = tokens[i].text
                i += 1
                if i < tokens.count, tokens[i].text == "=" {
                    let end = Syntax.expressionEnd(tokens, from: i + 1, stopAtComma: true)
                    bindings[name, default: []].append(tokens[(i + 1)..<end])
                    if Self.lampBlocks.contains(name) { redefined.insert(name) }
                    i = end
                } else {
                    // `for (const x of …)`, or declared without a value.
                    opaque.insert(name)
                }
            } else {
                break
            }
            if i < tokens.count, tokens[i].text == "=" {
                let end = Syntax.expressionEnd(tokens, from: i + 1, stopAtComma: true)
                i = end
            }
            guard i < tokens.count, tokens[i].text == "," else { break }
            i += 1
        }
        return i
    }

    mutating func markOpaque(_ tokens: ArraySlice<Token>) {
        for token in tokens where token.kind == .ident { opaque.insert(token.text) }
    }

    mutating func objectLiteral(_ tokens: [Token], at open: Int) {
        let close = Syntax.matching(tokens, open)
        for entry in Syntax.split(tokens[(open + 1)..<close], by: ",") {
            guard let first = entry.first else { continue }
            if first.text == "..." { wildAny = true; continue }
            if first.text == "[" { wildAny = true; continue }
            let colon = entry.firstIndex { $0.text == ":" }
            if let colon, colon == entry.startIndex + 1, first.kind == .ident || first.kind == .string || first.kind == .number {
                properties[first.kind == .string ? first.value : first.text, default: []].append(tokens[(colon + 1)..<entry.endIndex])
            } else if entry.count == 1, first.kind == .ident {
                // { url } is { url: url }
                properties[first.text, default: []].append(entry)
            }
        }
    }

    /// Element builders: function NAME(… tag …, … attrs …) { … createElement(tag) … for (… key in attrs) … setAttribute(key, …) }.
    mutating func findBuilders(_ tokens: [Token], script: Int) {
        var i = 0
        while i < tokens.count {
            var name: String?, paren = -1
            if tokens[i].text == "function", i + 2 < tokens.count, tokens[i + 1].kind == .ident, tokens[i + 2].text == "(" {
                name = tokens[i + 1].text; paren = i + 2
            } else if tokens[i].text == "function", i >= 2, tokens[i - 1].text == "=", tokens[i - 2].kind == .ident,
                      i + 1 < tokens.count, tokens[i + 1].text == "(" {
                name = tokens[i - 2].text; paren = i + 1
            }
            guard let name, paren >= 0 else { i += 1; continue }
            let close = Syntax.matching(tokens, paren)
            let params = Syntax.split(tokens[(paren + 1)..<close], by: ",").compactMap { $0.count == 1 ? $0.first?.text : nil }
            guard close + 1 < tokens.count, tokens[close + 1].text == "{" else { i += 1; continue }
            let bodyEnd = Syntax.matching(tokens, close + 1)
            let body = tokens[(close + 2)..<bodyEnd]
            if let tag = Syntax.call(body, "createElement").flatMap({ args in args.first.flatMap { $0.count == 1 ? params.firstIndex(of: $0.first!.text) : nil } }),
               let (key, attributes) = Syntax.forIn(body).flatMap({ loop in params.firstIndex(of: loop.object).map { (loop.key, $0) } }),
               Syntax.calls(body, "setAttribute").allSatisfy({ $0.first?.count == 1 && $0.first?.first?.text == key }) {
                builders[name] = (tag, attributes)
                builderBodies[script, default: []].append((close + 2)..<bodyEnd)
            }
            i = close + 1
        }
    }

    // MARK: Finding requests

    mutating func findRequests(_ tokens: [Token], script: Int) {
        let ownBodies = builderBodies[script] ?? []
        for i in tokens.indices {
            let token = tokens[i]
            let previous = i > 0 ? tokens[i - 1] : nil
            let afterDot = previous?.text == "."
            let receiver = afterDot && i >= 2 ? Syntax.receiver(tokens, dot: i - 1) : nil
            let calls = i + 1 < tokens.count && tokens[i + 1].text == "("
            let args = calls ? Syntax.split(tokens[(i + 2)..<Syntax.matching(tokens, i + 1)], by: ",") : []
            if token.kind == .string, token.value.contains("<") { joinedMarkup(tokens, at: i) }

            if token.kind == .ident, calls {
                let global = !afterDot || ["window", "self", "globalThis"].contains(receiver?.text ?? "")
                let name = token.text
                let lampBlock = receiver.map { Self.lampBlocks.contains($0.text) && !redefined.contains($0.text) } ?? false
                if name == "fetch", global {
                    request(shapes(args.first), .load, at: "fetch")
                } else if name == "importScripts", global {
                    args.forEach { request(shapes($0), .code, at: "importScripts") }
                } else if name == "import", !afterDot {
                    request(moduleShapes(args.first), .code, at: "import()")
                } else if name == "open", global, previous?.text != "new" {
                    // window.open: a page the person's browser opens.
                    request(shapes(args.first), .link, at: "window.open")
                } else if name == "open", afterDot, args.count >= 2, !lampBlock {
                    let first = args[0].first
                    let method = args[0].count == 1 && first?.kind == .string
                        && ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].contains(first!.value.uppercased())
                    // An XMLHttpRequest, or a receiver it can't tell opened with a method it can't read.
                    if method || kind(of: receiver) == "xhr" || (kind(of: receiver) == nil && args[0].count == 1 && first?.kind == .ident) {
                        request(shapes(args[1]), .load, at: "XMLHttpRequest.open")
                    }
                } else if name == "sendBeacon", afterDot {
                    request(shapes(args.first), .load, at: "sendBeacon")
                } else if name == "register", receiver?.text == "serviceWorker" {
                    request(shapes(args.first), .code, at: "service worker")
                } else if name == "assign" || name == "replace", receiver?.text == "location" {
                    request(shapes(args.first), .load, at: "location")
                } else if name == "setAttribute", afterDot, !ownBodies.contains(where: { $0.contains(i) }) {
                    attribute(args.first, args.count > 1 ? args[1] : nil, tag: kind(of: receiver))
                } else if ["load", "loadAsync", "setPath", "setResourcePath"].contains(name), afterDot, !lampBlock {
                    let loader = kind(of: receiver) == "loader" || receiver?.text == ")" && Syntax.newBefore(tokens, close: i - 2)?.hasSuffix("Loader") == true
                    if loader || (kind(of: receiver) == nil && createsLoaders) {
                        if let first = args.first, first.first?.text == "[" {
                            Syntax.split(first.dropFirst().dropLast(), by: ",").forEach { request(shapes($0), .load, at: "a loader") }
                        } else {
                            request(shapes(args.first), .load, at: "a loader")
                        }
                    }
                } else if ["text", "json", "image"].contains(name), receiver?.text == "LampAssets", lampBlock {
                    request(shapes(args.first).map(Self.ownFile), .load, at: "LampAssets")
                } else if let builder = builders[name], !afterDot, previous?.text != "function" {
                    built(builder, args)
                }
            }
            if token.kind == .ident, token.text == "new", i + 1 < tokens.count {
                var j = i + 1
                while j + 2 < tokens.count, tokens[j + 1].text == "." { j += 2 }
                let name = tokens[j].text
                let args = j + 1 < tokens.count && tokens[j + 1].text == "("
                    ? Syntax.split(tokens[(j + 2)..<Syntax.matching(tokens, j + 1)], by: ",") : []
                switch name {
                case "WebSocket", "EventSource", "Request", "Audio": if !args.isEmpty { request(shapes(args.first), .load, at: "new \(name)") }
                case "Worker", "SharedWorker": request(shapes(args.first), .code, at: "new \(name)")
                default: break
                }
            }
            // Static imports: import … from 'x', import 'x', export … from 'x'.
            if token.kind == .string, let previous, previous.text == "from" || previous.text == "import" {
                request(moduleShape(token.value), .code, at: "import")
            }
            // obj.src = …, a.href = …, location = …
            if token.kind == .ident, i + 1 < tokens.count, tokens[i + 1].text == "=" {
                let end = Syntax.expressionEnd(tokens, from: i + 2)
                let value = tokens[(i + 2)..<end]
                if afterDot {
                    let tag = kind(of: receiver)
                    // `background` and `data` are addresses only on the elements that have them (a 3D scene has a
                    // background color, a chart its data).
                    if ["src", "srcset", "poster", "action", "formAction"].contains(token.text) || token.text == "data" && tag == "object"
                        || token.text == "background" && (["body", "table", "td", "th"].contains(tag ?? "") || receiver?.text == "body") {
                        request(shapes(value), tag == "script" ? .code : .load, at: ".\(token.text) =")
                    } else if token.text == "href" {
                        request(shapes(value), tag == "a" || tag == "area" ? .link : .load, at: ".href =")
                    } else if token.text == "location", ["window", "document", "self", "top", "parent"].contains(receiver?.text ?? "") {
                        request(shapes(value), .load, at: "location =")
                    }
                } else if token.text == "location" {
                    request(shapes(value), .load, at: "location =")
                }
            }
        }
    }

    /// `'<a href="' + address + '">'`: a string that leaves an address attribute open, and what's joined after it.
    mutating func joinedMarkup(_ tokens: [Token], at index: Int) {
        guard let element = HTML.elements(tokens[index].value).last,
              let (attribute, value) = element.attributes.first(where: { $0.value.hasSuffix(HTML.open) }),
              let use = HTML.use(tag: element.tag, attribute: attribute, attributes: element.attributes) else { return }
        let start = WebReach.Shape.exact(String(value.dropLast()))
        var rest: [WebReach.Shape] = [.any]
        if index + 2 < tokens.count, tokens[index + 1].text == "+" {
            let end = Syntax.expressionEnd(tokens, from: index + 2)
            let operand = Syntax.split(tokens[(index + 2)..<end], by: "+").first ?? []
            rest = shapes(operand)
        }
        request(rest.map { Self.join(start, $0) }, use, at: "markup joined to a value")
    }

    /// setAttribute(name, value) on an element of `tag` (nil when it can't be told).
    mutating func attribute(_ name: ArraySlice<Token>?, _ value: ArraySlice<Token>?, tag: String?) {
        let names = shapes(name)
        let values = shapes(value)
        for shape in names {
            guard case .exact(let attribute) = shape else {
                // Some attribute: its value matters only if it could be an address.
                request(values, .load, at: "setAttribute with a name it can't tell")
                continue
            }
            if let use = HTML.use(tag: tag ?? "", attribute: attribute.lowercased()) { request(values, use, at: "setAttribute(\(attribute))") }
        }
    }

    /// A call of an element builder: each attribute of the object it's given, set on an element of the tag it's given.
    mutating func built(_ builder: (tag: Int, attributes: Int), _ args: [ArraySlice<Token>]) {
        guard builder.attributes < args.count else { return }
        let tags = builder.tag < args.count ? shapes(args[builder.tag]) : [.any]
        let object = args[builder.attributes]
        guard let open = object.first, open.text == "{", object.last?.text == "}" else {
            if !object.isEmpty, !(object.count == 1 && ["null", "undefined"].contains(object.first!.text)) {
                request([.any], .load, at: "an element builder given attributes it can't read")
            }
            return
        }
        for entry in Syntax.split(object.dropFirst().dropLast(), by: ",") {
            guard let key = entry.first else { continue }
            guard let colon = entry.firstIndex(where: { $0.text == ":" }), colon == entry.startIndex + 1,
                  key.kind == .ident || key.kind == .string else {
                if entry.count == 1, key.kind == .ident { continue }
                request([.any], .load, at: "an element builder given attributes it can't read")
                continue
            }
            let attribute = (key.kind == .string ? key.value : key.text).lowercased()
            let value = entry[(colon + 1)...]
            for tag in tags {
                guard case .exact(let name) = tag else {
                    if HTML.use(tag: "", attribute: attribute) != nil { request(shapes(value), .load, at: "an element builder") }
                    continue
                }
                if let use = HTML.use(tag: name.lowercased(), attribute: attribute) { request(shapes(value), use, at: "an element builder") }
            }
        }
    }

    // MARK: Values

    /// What a receiver is, from what its name is given: an element's tag, "xhr", "loader", "location", or nil.
    func kind(of receiver: Token?) -> String? {
        guard let receiver, receiver.kind == .ident else { return nil }
        if receiver.text == "location" { return "location" }
        guard !opaque.contains(receiver.text), let values = bindings[receiver.text], !values.isEmpty else { return nil }
        var kinds = Set<String?>()
        for value in values {
            let tokens = Array(value)
            if let index = tokens.firstIndex(where: { $0.text == "createElement" }), index + 2 < tokens.count, tokens[index + 2].kind == .string {
                kinds.insert(tokens[index + 2].value.lowercased())
            } else if tokens.first?.text == "new", tokens.count > 1 {
                var j = 1
                while j + 2 < tokens.count, tokens[j + 1].text == "." { j += 2 }
                let name = tokens[j].text
                kinds.insert(name == "XMLHttpRequest" ? "xhr" : name == "Image" ? "img" : name == "Audio" ? "audio" : name.hasSuffix("Loader") ? "loader" : nil)
            } else {
                kinds.insert(nil)
            }
        }
        return kinds.count == 1 ? kinds.first! : nil
    }

    var depth = 0
    var resolving: Set<String> = []

    mutating func shapes(_ tokens: ArraySlice<Token>?) -> [WebReach.Shape] {
        guard let tokens, !tokens.isEmpty else { return [.any] }
        guard depth < 24 else { return [.any] }
        depth += 1
        defer { depth -= 1 }
        let result = evaluate(tokens)
        return result.count > 48 ? [.any] : result
    }

    mutating func evaluate(_ tokens: ArraySlice<Token>) -> [WebReach.Shape] {
        var tokens = tokens
        while tokens.first?.text == "(", Syntax.matching(Array(tokens), 0) == tokens.count - 1 {
            tokens = tokens.dropFirst().dropLast()
        }
        if tokens.first?.text == "await" { tokens = tokens.dropFirst() }
        guard !tokens.isEmpty else { return [.any] }
        // c ? a : b
        if let question = Syntax.topLevel(tokens, "?"), let colon = Syntax.topLevel(tokens[(question + 1)...], ":") {
            return unique(shapes(tokens[(question + 1)..<colon]) + shapes(tokens[(colon + 1)...]))
        }
        for op in ["||", "??", "&&"] {
            let parts = Syntax.split(tokens, by: op)
            if parts.count > 1 { return unique(parts.flatMap { shapes($0) }) }
        }
        let terms = Syntax.split(tokens, by: "+")
        if terms.count > 1 {
            var result: [WebReach.Shape] = [.exact("")]
            for term in terms where !term.isEmpty {
                let next = shapes(term)
                result = unique(result.flatMap { left in next.map { Self.join(left, $0) } })
                if result.count > 48 { return [.any] }
            }
            return result
        }
        return term(tokens)
    }

    mutating func term(_ tokens: ArraySlice<Token>) -> [WebReach.Shape] {
        let list = Array(tokens)
        if list.count == 1 {
            let token = list[0]
            switch token.kind {
            case .string: touched.insert(token.value); return [.exact(token.value)]
            case .number: return [.exact(token.text)]
            case .template: return template(token)
            case .ident: return name(token.text)
            default: return [.any]
            }
        }
        // new URL(address, base)
        if list.count >= 4, list[0].text == "new", list[1].text == "URL", list[2].text == "(", Syntax.matching(list, 2) == list.count - 1 {
            let args = Syntax.split(tokens.dropFirst(3).dropLast(), by: ",")
            let addresses = shapes(args.first)
            guard args.count > 1 else { return addresses }
            let bases = shapes(args[1])
            return unique(addresses.flatMap { address -> [WebReach.Shape] in
                if case .exact(let text) = address, WebReach.destination(exact: text) == .local, !text.hasPrefix("data:") { return bases }
                if case .prefix(let text) = address, WebReach.destination(prefix: text) == .local { return bases }
                return [address]
            })
        }
        // The page's own address.
        let joined = list.map(\.text).joined()
        if ["location.href", "location.origin", "window.location.href", "window.location.origin", "document.baseURI",
            "document.location.href", "import.meta.url", "self.location.href"].contains(joined) { return [.page] }
        // A call: Lamp's blocks as lamp.js defines them, a few string functions, anything else unknown.
        if list.last?.text == ")", let open = Syntax.opening(list, list.count - 1), open > 0 {
            let callee = list[..<open].map(\.text).joined()
            let args = Syntax.split(tokens[(tokens.startIndex + open + 1)..<(tokens.endIndex - 1)], by: ",")
            switch callee {
            case "LampAssets.url" where !redefined.contains("LampAssets"): return shapes(args.first).map(Self.ownFile)
            case "String", "decodeURI": return shapes(args.first)
            case "encodeURIComponent", "encodeURI", "escape": return [.any]
            default:
                if callee.hasSuffix(".trim") || callee.hasSuffix(".toString") { return shapes(tokens[tokens.startIndex..<(tokens.startIndex + open - 2)]) }
                return [.any]
            }
        }
        // a.b.c: what property c is given.
        if list.count >= 3, list[list.count - 2].text == ".", list.last!.kind == .ident,
           stride(from: 1, to: list.count, by: 2).allSatisfy({ list[$0].text == "." }) {
            return property(list.last!.text)
        }
        return [.any]
    }

    mutating func template(_ token: Token) -> [WebReach.Shape] {
        var result: [WebReach.Shape] = [.exact(token.parts.first ?? "")]
        touched.insert(token.parts.first ?? "")
        for (index, hole) in token.holes.enumerated() {
            let inner = shapes(hole[...])
            result = unique(result.flatMap { left in inner.map { Self.join(left, $0) } })
            let text = index + 1 < token.parts.count ? token.parts[index + 1] : ""
            result = result.map { Self.join($0, .exact(text)) }
            if result.count > 48 { return [.any] }
        }
        return result
    }

    mutating func name(_ name: String) -> [WebReach.Shape] {
        if opaque.contains(name) || resolving.contains(name) { return [.any] }
        guard let values = bindings[name], !values.isEmpty else { return [.any] }
        resolving.insert(name)
        defer { resolving.remove(name) }
        var result = unique(values.flatMap { shapes($0) })
        // url += …: what it was, and more after.
        if appends.contains(name) { result = unique(result + result.map { Self.join($0, .any) }) }
        return result
    }

    mutating func property(_ name: String) -> [WebReach.Shape] {
        let key = "." + name
        if resolving.contains(key) { return [.any] }
        resolving.insert(key)
        defer { resolving.remove(key) }
        let values = (properties[name] ?? []) + wild
        guard !values.isEmpty, !wildAny else {
            // Still read what it's given, so its addresses count as followed.
            _ = (properties[name] ?? []).map { shapes($0) }
            return [.any]
        }
        return unique(values.flatMap { shapes($0) })
    }

    func moduleShapes(_ tokens: ArraySlice<Token>?) -> [WebReach.Shape] {
        guard let tokens, tokens.count == 1, tokens.first!.kind == .string else { return [.any] }
        return moduleShape(tokens.first!.value)
    }

    /// A module's name as the page's import map resolves it; a bare name with no entry fails to load, so reaches nothing.
    func moduleShape(_ specifier: String) -> [WebReach.Shape] {
        if specifier.hasPrefix(".") || specifier.hasPrefix("/") || WebReach.destination(exact: specifier) != .local { return [.exact(specifier)] }
        if let exact = imports[specifier] { return [.exact(exact)] }
        if let match = imports.keys.filter({ $0.hasSuffix("/") && specifier.hasPrefix($0) }).max(by: { $0.count < $1.count }) {
            return [.exact(imports[match]! + specifier.dropFirst(match.count))]
        }
        return [.exact("./" + specifier)]
    }

    /// LampAssets.url(name): the name without its leading slashes (lamp.js), so a web address stays one.
    static func ownFile(_ shape: WebReach.Shape) -> WebReach.Shape {
        switch shape {
        case .exact(let text): .exact(String(text.drop { $0 == "/" }))
        case .prefix(let text): text.allSatisfy({ $0 == "/" }) ? .any : .prefix(String(text.drop { $0 == "/" }))
        case .page, .any: shape
        }
    }

    static func join(_ left: WebReach.Shape, _ right: WebReach.Shape) -> WebReach.Shape {
        switch (left, right) {
        case (.page, _): .page
        case (.any, _): .any
        case (.prefix, _): left
        case (.exact(let a), .exact(let b)): .exact(a + b)
        case (.exact(let a), .prefix(let b)): .prefix(a + b)
        case (.exact(let a), .page): a.isEmpty ? .page : .prefix(a)
        case (.exact(let a), .any): a.isEmpty ? .any : .prefix(a)
        }
    }

    func unique(_ shapes: [WebReach.Shape]) -> [WebReach.Shape] {
        var seen = Set<WebReach.Shape>()
        return shapes.filter { seen.insert($0).inserted }
    }
}

// MARK: - JavaScript

private struct Lexer {
    let chars: [Character]
    var i = 0
    var nextID: Int

    init(text: String, nextID: Int) {
        chars = Array(text)
        self.nextID = nextID
    }

    mutating func tokens(untilBrace: Bool = false) -> [Token] {
        var out: [Token] = []
        var braces = 0
        var newline = false
        while i < chars.count {
            let c = chars[i]
            if c == "\n" || c == "\r" || c == "\u{2028}" { newline = true; i += 1; continue }
            if c.isWhitespace { i += 1; continue }
            if c == "/", peek(1) == "/" { while i < chars.count, chars[i] != "\n" { i += 1 }; continue }
            if c == "/", peek(1) == "*" {
                i += 2
                while i < chars.count, !(chars[i] == "*" && peek(1) == "/") { if chars[i] == "\n" { newline = true }; i += 1 }
                i += 2
                continue
            }
            var token: Token
            if c == "\"" || c == "'" {
                token = string(c)
            } else if c == "`" {
                token = template()
            } else if c.isLetter || c == "_" || c == "$" || c == "#" {
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "$" || chars[i] == "#" { i += 1 }
                token = Token(kind: .ident, text: String(chars[start..<i]))
            } else if c.isNumber || c == "." && (peek(1)?.isNumber ?? false) {
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "." || chars[i] == "_" { i += 1 }
                token = Token(kind: .number, text: String(chars[start..<i]))
            } else if c == "/", regexAllowed(after: out.last) {
                token = regex()
            } else {
                // The } that closes a template's ${…} is the template's.
                if untilBrace, c == "}", braces == 0 { return out }
                token = punct()
                if untilBrace, token.text == "{" { braces += 1 }
                if untilBrace, token.text == "}" { braces -= 1 }
            }
            token.newline = newline
            token.id = nextID
            nextID += 1
            newline = false
            out.append(token)
        }
        return out
    }

    func peek(_ offset: Int) -> Character? { i + offset < chars.count ? chars[i + offset] : nil }

    func regexAllowed(after token: Token?) -> Bool {
        guard let token else { return true }
        switch token.kind {
        case .ident: return ["return", "typeof", "case", "do", "else", "in", "of", "new", "delete", "void", "throw", "instanceof", "yield", "await"].contains(token.text)
        case .punct: return ![")", "]", "}"].contains(token.text)
        default: return false
        }
    }

    mutating func string(_ quote: Character) -> Token {
        let start = i
        i += 1
        var value = ""
        while i < chars.count, chars[i] != quote, chars[i] != "\n" {
            if chars[i] == "\\" { i += 1; value += escape() } else { value.append(chars[i]); i += 1 }
        }
        i += 1
        var token = Token(kind: .string, text: String(chars[start..<min(i, chars.count)]))
        token.value = value
        return token
    }

    mutating func escape() -> String {
        guard i < chars.count else { return "" }
        let c = chars[i]
        i += 1
        switch c {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "0": return "\0"
        case "\n": return ""
        case "x":
            let hex = String(chars[i..<min(i + 2, chars.count)])
            i += 2
            return UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init).map { String($0) } ?? ""
        case "u":
            var hex: String
            if peek(0) == "{" {
                let end = chars[i...].firstIndex(of: "}") ?? chars.count
                hex = String(chars[(i + 1)..<end])
                i = end + 1
            } else {
                hex = String(chars[i..<min(i + 4, chars.count)])
                i += 4
            }
            return UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init).map { String($0) } ?? ""
        default: return String(c)
        }
    }

    mutating func template() -> Token {
        i += 1
        var parts: [String] = [], holes: [[Token]] = []
        var current = ""
        while i < chars.count, chars[i] != "`" {
            if chars[i] == "\\" { i += 1; current += escape(); continue }
            if chars[i] == "$", peek(1) == "{" {
                i += 2
                parts.append(current)
                current = ""
                holes.append(tokens(untilBrace: true))
                i += 1
                continue
            }
            current.append(chars[i])
            i += 1
        }
        i += 1
        parts.append(current)
        var token = Token(kind: .template, text: "`")
        token.parts = parts
        token.holes = holes
        return token
    }

    mutating func regex() -> Token {
        let start = i
        i += 1
        var inClass = false
        while i < chars.count, chars[i] != "\n" {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "[" { inClass = true } else if chars[i] == "]" { inClass = false } else if chars[i] == "/", !inClass { break }
            i += 1
        }
        i += 1
        while i < chars.count, chars[i].isLetter { i += 1 }
        return Token(kind: .regex, text: String(chars[start..<min(i, chars.count)]))
    }

    static let operators = [">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=",
                            "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--", "+=", "-=", "*=", "/=", "%=",
                            "&=", "|=", "^=", "<<", ">>", "**"]

    mutating func punct() -> Token {
        for op in Self.operators where matches(op) {
            // ?. before a digit is a ternary and a number.
            if op == "?.", let next = peek(2), next.isNumber { break }
            i += op.count
            return Token(kind: .punct, text: op)
        }
        i += 1
        return Token(kind: .punct, text: String(chars[i - 1]))
    }

    func matches(_ op: String) -> Bool {
        var j = i
        for c in op {
            guard j < chars.count, chars[j] == c else { return false }
            j += 1
        }
        return true
    }
}

private enum Syntax {
    static let open: [String: String] = ["(": ")", "[": "]", "{": "}"]

    /// The index of the bracket that closes the one at `index` (the end when it's never closed).
    static func matching<C: RandomAccessCollection>(_ tokens: C, _ index: C.Index) -> C.Index where C.Element == Token {
        guard let close = open[tokens[index].text] else { return index }
        let opener = tokens[index].text
        var depth = 0
        var j = index
        while j < tokens.endIndex {
            if tokens[j].text == opener { depth += 1 } else if tokens[j].text == close { depth -= 1; if depth == 0 { return j } }
            j = tokens.index(after: j)
        }
        return tokens.index(before: tokens.endIndex)
    }

    /// The index of the bracket that opens the one closing at `index`.
    static func opening<C: BidirectionalCollection>(_ tokens: C, _ index: C.Index) -> C.Index? where C.Element == Token {
        let pairs = [")": "(", "]": "[", "}": "{"]
        guard let opener = pairs[tokens[index].text] else { return nil }
        let closer = tokens[index].text
        var depth = 0
        var j = index
        while true {
            if tokens[j].text == closer { depth += 1 } else if tokens[j].text == opener { depth -= 1; if depth == 0 { return j } }
            if j == tokens.startIndex { return nil }
            j = tokens.index(before: j)
        }
    }

    /// Splits at `separator` where it isn't inside brackets.
    static func split(_ tokens: ArraySlice<Token>, by separator: String) -> [ArraySlice<Token>] {
        var parts: [ArraySlice<Token>] = []
        var depth = 0, start = tokens.startIndex
        var j = tokens.startIndex
        while j < tokens.endIndex {
            let text = tokens[j].text
            if open[text] != nil { depth += 1 } else if [")", "]", "}"].contains(text) { depth -= 1 }
            else if depth == 0, text == separator, tokens[j].kind == .punct {
                // A leading + is a sign, not a join.
                if !(separator == "+" && (j == tokens.startIndex || tokens[j - 1].kind == .punct && ![")", "]", "}"].contains(tokens[j - 1].text))) {
                    parts.append(tokens[start..<j])
                    start = j + 1
                }
            }
            j += 1
        }
        parts.append(tokens[start..<tokens.endIndex])
        return parts.count == 1 && parts[0].isEmpty ? [] : parts
    }

    static func topLevel(_ tokens: ArraySlice<Token>, _ text: String) -> Int? {
        var depth = 0
        for j in tokens.indices {
            let t = tokens[j].text
            if open[t] != nil { depth += 1 } else if [")", "]", "}"].contains(t) { depth -= 1 }
            else if depth == 0, t == text, tokens[j].kind == .punct { return j }
        }
        return nil
    }

    /// Where an expression that starts at `start` ends: a ; , or closing bracket outside brackets, or a new line where
    /// the expression could already have ended.
    static func expressionEnd(_ tokens: [Token], from start: Int, stopAtComma: Bool = true) -> Int {
        var depth = 0
        var j = start
        while j < tokens.count {
            let token = tokens[j]
            if depth == 0 {
                if token.text == ";" || (stopAtComma && token.text == ",") || [")", "]", "}"].contains(token.text) { return j }
                // A line that starts a new statement after one that could have ended.
                if j > start, token.newline, case let previous = tokens[j - 1], previous.kind != .punct || [")", "]", "}"].contains(previous.text),
                   token.kind != .punct, !["in", "of", "instanceof"].contains(token.text) {
                    return j
                }
            }
            if open[token.text] != nil { depth += 1 } else if [")", "]", "}"].contains(token.text) { depth -= 1 }
            j += 1
        }
        return j
    }

    /// Whether the brace at `index` opens an object literal rather than a block.
    static func isObjectLiteral(_ tokens: [Token], at index: Int) -> Bool {
        guard index > 0 else { return false }
        let previous = tokens[index - 1]
        if previous.kind == .ident { return ["return", "yield", "await", "typeof", "in", "of", "case"].contains(previous.text) }
        return ["=", "(", ",", ":", "[", "?", "??", "||", "&&", "...", "!"].contains(previous.text)
    }

    /// What's before the dot at `dot`: the name, or the closing bracket of a call or index.
    static func receiver(_ tokens: [Token], dot: Int) -> Token? {
        dot > 0 ? tokens[dot - 1] : nil
    }

    /// `new X.YLoader(...)` closing at `close`: the class's name.
    static func newBefore(_ tokens: [Token], close: Int) -> String? {
        guard close >= 0, let open = opening(tokens, close), open >= 2 else { return nil }
        var j = open - 1
        while j >= 2, tokens[j - 1].text == "." { j -= 2 }
        return j >= 1 && tokens[j - 1].text == "new" ? tokens[open - 1].text : nil
    }

    /// The first call of `name` in `tokens`: its arguments.
    static func call(_ tokens: ArraySlice<Token>, _ name: String) -> [ArraySlice<Token>]? {
        calls(tokens, name).first
    }

    static func calls(_ tokens: ArraySlice<Token>, _ name: String) -> [[ArraySlice<Token>]] {
        var found: [[ArraySlice<Token>]] = []
        for j in tokens.indices where tokens[j].text == name && j + 1 < tokens.endIndex && tokens[j + 1].text == "(" {
            let close = matching(tokens, j + 1)
            found.append(split(tokens[(j + 2)..<close], by: ","))
        }
        return found
    }

    /// The first `for (var key in object)` in `tokens`.
    static func forIn(_ tokens: ArraySlice<Token>) -> (key: String, object: String)? {
        for j in tokens.indices where tokens[j].text == "for" && j + 1 < tokens.endIndex && tokens[j + 1].text == "(" {
            let close = matching(tokens, j + 1)
            let inside = Array(tokens[(j + 2)..<close])
            guard let at = inside.firstIndex(where: { $0.text == "in" }), at >= 1, inside[at - 1].kind == .ident else { continue }
            let rest = inside[(at + 1)...].filter { !["||", "{", "}"].contains($0.text) }
            guard let object = rest.first, object.kind == .ident else { continue }
            return (inside[at - 1].text, object.text)
        }
        return nil
    }
}

// MARK: - HTML and CSS

private enum HTML {
    /// Stands in a string for a template's `${…}`: what can't be told.
    static let hole = "\u{E000}"
    /// Ends a value a string leaves open (`'<a href="' + address`), which the code joining it goes on with.
    static let open = "\u{E001}"

    struct Element {
        let tag: String
        var attributes: [String: String]
        var body: String
    }

    /// Every element's tag and attributes, with a script's or style's text as its body.
    static func elements(_ text: String) -> [Element] {
        var out: [Element] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            guard chars[i] == "<" else { i += 1; continue }
            if i + 3 < chars.count, chars[i + 1] == "!", chars[i + 2] == "-", chars[i + 3] == "-" {
                var j = i + 4
                while j + 2 < chars.count, !(chars[j] == "-" && chars[j + 1] == "-" && chars[j + 2] == ">") { j += 1 }
                i = j + 3
                continue
            }
            var j = i + 1
            guard j < chars.count, chars[j].isLetter else { i += 1; continue }
            while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "-" { j += 1 }
            let tag = String(chars[(i + 1)..<j]).lowercased()
            var attributes: [String: String] = [:]
            while j < chars.count, chars[j] != ">" {
                while j < chars.count, chars[j].isWhitespace || chars[j] == "/" { j += 1 }
                let nameStart = j
                while j < chars.count, !chars[j].isWhitespace, !"=>/".contains(chars[j]) { j += 1 }
                let name = String(chars[nameStart..<j]).lowercased()
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                var value = ""
                if j < chars.count, chars[j] == "=" {
                    j += 1
                    while j < chars.count, chars[j].isWhitespace { j += 1 }
                    if j < chars.count, chars[j] == "\"" || chars[j] == "'" {
                        let quote = chars[j]
                        let start = j + 1
                        j = start
                        while j < chars.count, chars[j] != quote { j += 1 }
                        value = String(chars[start..<min(j, chars.count)])
                        // Left open where the string ends: what's joined after it goes on the value.
                        if j >= chars.count { value += open }
                        j += 1
                    } else {
                        let start = j
                        while j < chars.count, !chars[j].isWhitespace, chars[j] != ">" { j += 1 }
                        value = String(chars[start..<j])
                    }
                }
                if !name.isEmpty { attributes[name] = decode(value) }
                if nameStart == j { j += 1 }
            }
            j += 1
            var element = Element(tag: tag, attributes: attributes, body: "")
            if tag == "script" || tag == "style" {
                let close = "</\(tag)"
                let rest = String(chars[min(j, chars.count)...])
                if let end = rest.range(of: close, options: .caseInsensitive) {
                    element.body = String(rest[..<end.lowerBound])
                    j += rest.distance(from: rest.startIndex, to: end.lowerBound)
                } else {
                    element.body = rest
                    j = chars.count
                }
            }
            out.append(element)
            i = j
        }
        return out
    }

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                               ("&colon;", ":"), ("&#58;", ":"), ("&sol;", "/"), ("&#47;", "/")] {
            out = out.replacingOccurrences(of: entity, with: char, options: .caseInsensitive)
        }
        return out
    }

    /// The attributes of `tag` whose value is an address, and whether it's loaded, run as code or a link.
    static func urlAttributes(tag: String, attributes: [String: String]) -> [(String, Use)] {
        attributes.keys.compactMap { name in use(tag: tag, attribute: name, attributes: attributes).map { (name, $0) } }
    }

    static func use(tag: String, attribute: String, attributes: [String: String] = [:]) -> Use? {
        switch attribute {
        case "href", "xlink:href":
            if tag == "a" || tag == "area" { return .link }
            if tag == "link", let rel = attributes["rel"]?.lowercased(),
               rel.split(separator: " ").allSatisfy({ ["author", "license", "help", "bookmark", "canonical", "alternate", "next", "prev", "search", "me"].contains($0) }) {
                return .link
            }
            return tag == "link" && attributes["rel"]?.lowercased().contains("modulepreload") == true ? .code : .load
        case "src": return tag == "script" || tag == "iframe" || tag == "frame" || tag == "embed" ? .code : .load
        case "srcset", "poster", "background", "action", "formaction", "data", "ping", "manifest", "codebase", "archive", "lowsrc", "dynsrc":
            return attribute == "data" && tag != "object" && !tag.isEmpty ? nil : .load
        default: return nil
        }
    }

    static func srcset(_ value: String) -> [String] {
        value.split(separator: ",").compactMap { $0.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) }
    }

    /// An attribute's value as written in a string, its `${…}`s unknown.
    static func shape(_ value: String) -> WebReach.Shape {
        let value = value.replacingOccurrences(of: open, with: hole)
        guard let hole = value.range(of: hole) else { return .exact(value) }
        let start = String(value[..<hole.lowerBound])
        return start.isEmpty ? .any : .prefix(start)
    }

    /// Web addresses written inside markup or a style in a string, which `fragments` reads.
    static func addressesInMarkup(_ text: String) -> [String] {
        var found: [String] = []
        for element in elements(text) {
            for (attribute, _) in urlAttributes(tag: element.tag, attributes: element.attributes) {
                if let value = element.attributes[attribute] { found.append(contentsOf: attribute == "srcset" ? srcset(value) : [value]) }
            }
        }
        return found
    }
}

private enum CSS {
    /// The addresses a style loads: url(…), @import and image-set(…), what can't be told as unknown.
    static func addresses(_ text: String) -> [WebReach.Shape] {
        var source = text
        while let open = source.range(of: "/*"), let close = source.range(of: "*/", range: open.upperBound..<source.endIndex) {
            source.removeSubrange(open.lowerBound..<close.upperBound)
        }
        var found: [WebReach.Shape] = []
        var rest = Substring(source)
        while let match = rest.range(of: #"(url|image-set|@import)\s*\(?\s*"#, options: [.regularExpression, .caseInsensitive]) {
            var after = rest[match.upperBound...]
            if let quote = after.first, quote == "\"" || quote == "'" {
                after = after.dropFirst()
                let end = after.firstIndex(of: quote) ?? after.endIndex
                found.append(HTML.shape(String(after[..<end])))
                rest = after[end...].dropFirst()
            } else if rest[match].lowercased().hasPrefix("url") {
                let end = after.firstIndex(where: { $0 == ")" || $0.isWhitespace }) ?? after.endIndex
                let value = String(after[..<end])
                found.append(value.isEmpty && end == after.endIndex ? .any : HTML.shape(value))
                rest = after[end...]
            } else {
                rest = after
            }
        }
        return found
    }
}

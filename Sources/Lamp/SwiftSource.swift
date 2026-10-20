import Foundation
import CryptoKit

/// What Lamp's live rewrites need to know about the app's source, read from the compiler's own syntax tree (the
/// `-dump-ast` that `LiveReload.layout` already runs) rather than from the text: where each stored property is
/// declared, with what, and which types SwiftUI reads only at launch. The compiler has already found every string,
/// comment, attribute and comma, so nothing here has to.
enum SwiftSource {
    /// A place in a file as the compiler gives it: 1-based line, and column in UTF-8 bytes.
    struct Position: Hashable {
        var file: String
        var line: Int
        var column: Int
    }

    /// One `var`/`let` declaration (from its keyword to the start of its last token) and the names it declares.
    struct Binding {
        var start: Position
        var last: Position
        var entries: [Entry]
    }

    struct Entry {
        var name: String
        /// The start and last token of its starting value, when it has one.
        var initial: (start: Position, last: Position)?
        /// Whether that value is a literal by the compiler's word (a string, a number, a Bool, nil), however it's
        /// spelt (`"a\nb"`, `0xFF`, `-1.5e3`): the same every time it's made.
        var literal = false
    }

    /// A property as declared in the source, by "Type<tab>name".
    struct Variable {
        var name: String
        var position: Position
        var type: String
        var binding: Int
        /// Its attributes, each from its `@` to the start of its name's last token, with that name.
        var attributes: [(start: Position, last: Position, name: String)]
        /// Something a computed property kept in a spare couldn't do the same: observers (`didSet`, `willSet`),
        /// `lazy`, or a reference held weakly or unowned.
        var special = false
    }

    struct Declarations {
        var bindings: [Binding] = []
        var variables: [String: Variable] = [:]
        /// Static and global `let`s, by "Type<tab>name" ("<tab>name" for a global).
        var constants: [String: Variable] = [:]
        /// Stored static and global `var`s with a starting value, keyed the same: the open app made each once and keeps
        /// it, so a new starting value can't show without reopening.
        var stored: [String: Variable] = [:]
        /// The app's own classes, whose objects a constant may hold.
        var classes: Set<String> = []
        /// Each type's memberwise initializers that the compiler made itself and code outside the type can call: their
        /// labels and parameter types in order (`init(a:c:)`, `[Int, [Int]?]`). What a struct's code calls to make one.
        var memberwise: [String: [(labels: [String], types: [String])]] = [:]
        /// The same for a memberwise initializer that's private to the type's file (a private stored property makes it
        /// so): an extension in that file can call it, one in another can't.
        var privateMemberwise: [String: [(labels: [String], types: [String])]] = [:]
        /// Each type's initializers written in its code, its extensions' included: labels and parameter types, as
        /// `memberwise` has them, so one can be told from another with the same labels and other types.
        var initializers: [String: [(labels: [String], types: [String])]] = [:]
        /// Where each type's own declaration runs, by its qualified name: what a view's `$name` means is its own.
        var types: [String: (start: Position, last: Position)] = [:]
        /// Where each extension runs, by the name it extends as written (`Row`, `Shelf.Row`): a view's `$name` means
        /// its own there too.
        var extensions: [String: [(start: Position, last: Position)]] = [:]
        /// The types private to their file, which an extension in another file can't reach.
        var privateTypes: Set<String> = []
        /// The stored properties declared with `let` ("Type<tab>name").
        var lets: Set<String> = []
        /// The properties set in an initializer the type writes itself ("Type<tab>name"): a computed property kept
        /// in a spare can't be set before the stored ones are, so such a property stays stored.
        var assigned: Set<String> = []
        /// Where each declaration a call can name runs (a function, an initializer, a subscript, a property with what
        /// makes it), and every call to one of the app's, from where it's made to where what it names is declared:
        /// a constant's value is made by what it calls, as far down as that goes (`constantEntries`).
        var bodies: [(start: Position, last: Position)] = []
        var calls: [(at: Position, to: Position)] = []
        /// Each type's own `hash(into:)`, by its qualified name: sets and dictionaries the open app keeps were laid out
        /// by it (`hashEntries`).
        var hashing: [String: (start: Position, last: Position)] = [:]
    }

    /// A printout's line that opens a node: its indent and the node's name, the run of letters, digits, `_` and `=`
    /// after its `(` (`var_decl`, `original_init=closure_expr`), read without a regex.
    struct Node {
        var indent: Int
        var name: Substring
        /// Whether the name begins with one of these. Every pattern read off a printout begins at a node's `(`, so one
        /// for nodes this one's name rules out can't match its line, and isn't tried: the printout is tens of megabytes
        /// for a big app, and a regex tried on every line of it costs seconds.
        func opens(_ names: String...) -> Bool { names.contains { name.utf8.starts(with: $0.utf8) } }
        func names(_ part: String) -> Bool { SwiftSource.has(String(name), part) }
    }

    /// The node a line opens; nil for any other line (the closing brackets of a deep node sometimes come on a line of
    /// their own).
    static func node(_ line: Substring) -> Node? {
        let bytes = line.utf8
        var at = bytes.startIndex, indent = 0
        while at != bytes.endIndex, bytes[at] == UInt8(ascii: " ") { indent += 1; at = bytes.index(after: at) }
        guard at != bytes.endIndex, bytes[at] == UInt8(ascii: "(") else { return nil }
        let start = bytes.index(after: at)
        var end = start
        while end != bytes.endIndex, case let b = bytes[end],
              b == UInt8(ascii: "_") || b == UInt8(ascii: "=") || (b >= 48 && b <= 57) || (b | 0x20 >= 97 && b | 0x20 <= 122) {
            end = bytes.index(after: end)
        }
        return Node(indent: indent, name: Substring(bytes[start..<end]))
    }

    /// A printout's lines, split by their bytes rather than as characters, which costs as much again as reading them.
    static func lines(_ dump: String) -> [Substring] {
        dump.utf8.split(separator: UInt8(ascii: "\n")).map { Substring($0) }
    }

    /// Whether a line holds `text`, by its bytes: Foundation's `contains` goes through NSString, which costs as
    /// much as a regex on a line this long, and the standard library's search a good deal more.
    static func has(_ line: String, _ text: String) -> Bool {
        var line = line, text = text
        return line.withUTF8 { haystack in
            text.withUTF8 { needle in
                guard let at = haystack.baseAddress, let what = needle.baseAddress else { return needle.isEmpty }
                return memmem(at, haystack.count, what, needle.count) != nil
            }
        }
    }

    private static let rangePattern = try! NSRegularExpression(pattern: #"range=\[([^\]]+?):(\d+):(\d+) - line:(\d+):(\d+)\]"#)

    /// Where what a reference names is declared, when it's the app's own code (`decl="Case.(file).build()@<file>:3:6"`);
    /// the system's declarations carry no place.
    static func declared(in line: String) -> Position? {
        guard let open = line.range(of: " decl=\""), let close = line[open.upperBound...].firstIndex(of: "\""),
              case let value = line[open.upperBound..<close], let at = value.lastIndex(of: "@") else { return nil }
        let place = value[value.index(after: at)...].split(separator: ":")
        guard place.count >= 3, let row = Int(place[place.count - 2]), let column = Int(place[place.count - 1]) else { return nil }
        let file = place.dropLast(2).joined(separator: ":")
        guard !file.hasPrefix("__swiftmacro"), file.hasSuffix(".swift") else { return nil }
        return Position(file: file, line: row, column: column)
    }

    static func range(in line: String) -> (start: Position, last: Position)? {
        guard let m = rangePattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        func group(_ i: Int) -> String { String(line[Range(m.range(at: i), in: line)!]) }
        let file = group(1)
        // What macros wrote isn't in any file of the app's.
        guard !file.hasPrefix("@__swiftmacro") else { return nil }
        return (Position(file: file, line: Int(group(2))!, column: Int(group(3))!),
                Position(file: file, line: Int(group(4))!, column: Int(group(5))!))
    }

    /// Every property declared in a type of the app's, with its declaration.
    static func declarations(inDump dump: String) -> Declarations {
        let reader = DeclarationsReader()
        walk(dump, reader.take)
        return reader.finish()
    }

    /// Reads where each property is declared, line by line as `walk` gives them.
    final class DeclarationsReader {
        private let varDecl = try! NSRegularExpression(pattern: #"^(\s*)\(var_decl\b[^"]*"([^"]+)" interface_type="([^"]*)"(.*)$"#)
        private let named = try! NSRegularExpression(pattern: #"\(pattern_named\b.*"([^"]+)"\)*\s*$"#)
        private let identifier = try! NSRegularExpression(pattern: #"id="(\w+)""#)
        // An observer's accessor, with the property it's for: under @Observable the macro moves a property's
        // didSet to its `_name` storage in a buffer of its own, and @Published folds it into the wrapper's setter, so
        // the property's own line no longer says it has observers.
        private let observer = try! NSRegularExpression(pattern: #"^\s*\(accessor_decl\b.*? (?:didSet|willSet) for="(\w+)""#)
        // An assignment in an initializer the type writes: the node under it says what's set.
        private let assigned = try! NSRegularExpression(pattern: #"^(\s*)\(member_ref_expr\b.*? decl="[^"]*?\.(\w+)@"#)
        private var observed = Set<String>()
        private var out = Declarations()
        // The initializer being read, and an assignment in it whose target is the next node.
        private var initializer: (indent: Int, owner: String)?, assignment: Int?
        // The binding being read, at its indent, and what's inside it.
        private var binding: (indent: Int, index: Int)?
        private var entryOpen = false
        private var variable: (indent: Int, key: String)?
        private var attribute: (start: Position, last: Position)?

        func take(_ line: Walk.Line) {
            let indent = line.indent, opens = line.opens
            if opens("func_decl", "constructor_decl", "subscript_decl", "pattern_binding_decl"), !line.has(" implicit"),
               let r = SwiftSource.range(in: line.text) {
                out.bodies.append(r)
                if opens("func_decl"), line.has(" \"hash(into:)\" "), let owner = line.owner { out.hashing[owner] = r }
            } else if line.has(" decl=\""), let to = SwiftSource.declared(in: line.text), let at = SwiftSource.range(in: line.text)?.start {
                out.calls.append((at, to))
            }
            if let open = binding, indent <= open.indent { binding = nil }
            if let open = variable, indent <= open.indent { variable = nil; attribute = nil }
            if let open = initializer, indent <= open.indent { initializer = nil; assignment = nil }
            if let open = initializer {
                if let at = assignment {
                    if indent == at + 2, opens("member_ref_expr"), let m = assigned.firstMatch(in: line.text, range: line.range) { out.assigned.insert(open.owner + "\t" + String(line.text[Range(m.range(at: 2), in: line.text)!])) }
                    assignment = nil
                }
                if opens("assign_expr") { assignment = indent }
                return
            }
            // A protocol's requirements aren't declarations with storage.
            let owner = line.owner.flatMap { $0.hasPrefix("protocol ") ? nil : $0 }
            if let type = line.type {
                // By its key and by its bare last name, which a type's words in a constant's type name it by.
                if type.kind == "class" { out.classes.insert(type.key); out.classes.insert(String(LiveReload.bare(type.key).split(separator: ".").last ?? "")) }
                if let r = type.range { out.types[type.key] = r }
                if type.isPrivate { out.privateTypes.insert(type.key) }
                return
            }
            if let extended = line.extensionOf {
                if let r = SwiftSource.range(in: line.text) { out.extensions[extended, default: []].append(r) }
                return
            }
            if let owner, opens("accessor_decl"), let m = observer.firstMatch(in: line.text, range: line.range) {
                var name = String(line.text[Range(m.range(at: 1), in: line.text)!])
                if name.hasPrefix("_") { name.removeFirst() }
                observed.insert(owner + "\t" + name)
            }
            if line.function != nil {
                // A convenience initializer sets properties only after `self.init`, when a computed one can be set.
                if let owner, opens("constructor_decl"), !line.has(" implicit ") {
                    if !line.has(" convenience") { initializer = (indent, owner) }
                    if let made = SwiftSource.memberwise(in: line.text) { out.initializers[owner, default: []].append(made) }
                }
                if let owner, opens("constructor_decl"), line.has(" implicit "),
                   let made = SwiftSource.memberwise(in: line.text), !made.labels.isEmpty {
                    if line.has("access=private") || line.has("access=fileprivate") { out.privateMemberwise[owner, default: []].append(made) }
                    else { out.memberwise[owner, default: []].append(made) }
                }
                return
            }
            if let open = binding {
                // Inside a binding: its entries, each with its name and its starting value.
                if opens("pattern_entry") { out.bindings[open.index].entries.append(Entry(name: "", initial: nil)); entryOpen = true; return }
                if entryOpen, var entry = out.bindings[open.index].entries.last {
                    if entry.name.isEmpty, line.has("(pattern_named"), let m = named.firstMatch(in: line.text, range: line.range) {
                        entry.name = String(line.text[Range(m.range(at: 1), in: line.text)!])
                    } else if entry.initial == nil, line.has("(original_init=") || line.has("(processed_init="),
                              let r = SwiftSource.range(in: line.text) {
                        // As written, or (when that's unresolved and has no place) as the compiler settled it.
                        entry.initial = r
                        let kind = line.node.name.split(separator: "=").last ?? ""
                        entry.literal = ["string_literal_expr", "integer_literal_expr", "float_literal_expr", "boolean_literal_expr", "nil_literal_expr"].contains(String(kind))
                    }
                    out.bindings[open.index].entries[out.bindings[open.index].entries.count - 1] = entry
                }
                return
            }
            if let open = variable {
                // Inside a property: its attributes, each a range followed by the name it uses.
                if opens("reference_ownership_attr") { out.variables[open.key]?.special = true; return }
                if opens("custom_attr"), let r = SwiftSource.range(in: line.text) { attribute = r; return }
                if let r = attribute, line.has("id=\""), let m = identifier.firstMatch(in: line.text, range: line.range) {
                    out.variables[open.key]?.attributes.append((r.start, r.last, String(line.text[Range(m.range(at: 1), in: line.text)!])))
                    attribute = nil
                }
                return
            }
            // A type's members, and the file's own globals.
            let global = line.isTopLevel
            guard owner != nil || global else { return }
            if opens("pattern_binding_decl"), let r = SwiftSource.range(in: line.text) {
                out.bindings.append(Binding(start: r.start, last: r.last, entries: []))
                binding = (indent, out.bindings.count - 1)
                entryOpen = false
                return
            }
            if opens("var_decl"), let m = varDecl.firstMatch(in: line.text, range: line.range), let r = SwiftSource.range(in: line.text), let index = out.bindings.indices.last {
                let name = String(line.text[Range(m.range(at: 2), in: line.text)!])
                guard out.bindings[index].entries.contains(where: { $0.name == name }) else { return }
                let isStatic = line.has(" static"), rest = String(line.text[Range(m.range(at: 4), in: line.text)!])
                if isStatic || global {
                    // A constant: a static or global `let` with a starting value.
                    // A private or file-private one is the file's own: another file may have one by the same name.
                    let own = rest.contains("access=private") || rest.contains("access=fileprivate")
                    let place = own ? "@" + (r.start.file as NSString).lastPathComponent : ""
                    let made = Variable(name: name, position: r.start, type: String(line.text[Range(m.range(at: 3), in: line.text)!]),
                                        binding: index, attributes: [])
                    if rest.contains(" let ") { out.constants[(owner ?? "") + "\t" + name + place] = made }
                    else if rest.contains("readImpl=stored") { out.stored[(owner ?? "") + "\t" + name + place] = made }
                    return
                }
                guard let owner else { return }
                let key = owner + "\t" + name
                out.variables[key] = Variable(name: name, position: r.start, type: String(line.text[Range(m.range(at: 3), in: line.text)!]),
                                              binding: index, attributes: [],
                                              special: rest.contains("with_observers") || rest.contains(" lazy "))
                if rest.contains(" let ") { out.lets.insert(key) }
                variable = (indent, key)
            }
        }

        func finish() -> Declarations {
            for key in observed { out.variables[key]?.special = true }
            return out
        }
    }

    /// What a function, accessor or closure is called where a type declared inside it is keyed by it: its quoted
    /// name (`pick(_:another:)`, `init()`), else the node's kind (`closure_expr`, `accessor_decl`).
    static func scopeName(_ line: String) -> String {
        if let open = line.firstIndex(of: "\""), let close = line[line.index(after: open)...].firstIndex(of: "\"") {
            return String(line[line.index(after: open)..<close])
        }
        return String(line.drop { $0 == " " }.dropFirst().prefix { $0 != " " && $0 != ")" })
    }

    /// An implicit initializer's labels and parameter types, from its line in the dump: `"init(a:c:)"` and
    /// `interface_type="(P.Type) -> (Int, [Int]?) -> P"`. Nil for one whose parameters can't be told apart.
    static func memberwise(in line: String) -> (labels: [String], types: [String])? {
        guard let name = line.range(of: #""init\(([^)"]*)\)""#, options: .regularExpression),
              let type = line.range(of: #"interface_type=""#) else { return nil }
        let labels = line[name].dropFirst(6).dropLast(2).split(separator: ":", omittingEmptySubsequences: false).dropLast().map(String.init)
        // The parameters are the second parenthesised group: after "(P.Type) -> ".
        let rest = line[type.upperBound...]
        guard let arrow = rest.range(of: ") -> (") else { return nil }
        var depth = 0, current = "", types: [String] = []
        for ch in rest[arrow.upperBound...] {
            if depth == 0, ch == ")" { types.append(current.trimmingCharacters(in: .whitespaces)); break }
            if depth == 0, ch == "," { types.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue }
            if "([<".contains(ch) { depth += 1 } else if ")]>".contains(ch), current.last != "-" { depth -= 1 }
            current.append(ch)
        }
        guard types.count == labels.count, !types.contains(where: \.isEmpty) else { return nil }
        return (labels, types)
    }

    /// The types SwiftUI or AppKit read only at launch, at any depth: the App, its scenes, its menu commands and
    /// an application delegate, with extensions of them. Each is "\u{1}launch<tab>Name: <digest of its text>",
    /// entries the layout comparison holds to what the open app had, so a change to one reopens the app.
    /// A SwiftData model class is listed the same, as "model Name" with a digest of its whole file: its accessors
    /// find its data by key paths, which a library compiled from its file makes over again under identities the
    /// app's container doesn't know, so any change to that file reopens the app. Read line by line as `walk`
    /// gives them.
    final class LaunchReader {
        private let launch = try! NSRegularExpression(pattern: #"inherits="[^"]*\b(App|Scene|Commands|NSApplicationDelegate|UIApplicationDelegate)\b"#)
        private let model = try! NSRegularExpression(pattern: #"^(\s*)\(custom_attr\b.*macro="SwiftData\.\(file\)\.Model\(\)""#)
        private var types: [(name: String, range: (start: Position, last: Position), isExtension: Bool)] = []
        private var launchNames = Set<String>(), modelNames = Set<String>()
        private var lastClass: (name: String, indent: Int)?

        func take(_ line: Walk.Line) {
            if let last = lastClass, line.opens("custom_attr"), line.indent == last.indent + 2, model.firstMatch(in: line.text, range: line.range) != nil {
                modelNames.insert(last.name)
            }
            // By the name as written: a conformance may be declared on the type or on an extension of it (`extension Demo: App`).
            let name: String, kind: String
            if let type = line.type, type.kind != "actor" {
                name = String(LiveReload.bare(type.key).split(separator: ".").last ?? ""); kind = type.kind
            } else if let extended = line.extensionOf {
                name = extended; kind = "extension"
            } else { return }
            guard let r = SwiftSource.range(in: line.text) else { return }
            if launch.firstMatch(in: line.text, range: line.range) != nil { launchNames.insert(name) }
            lastClass = kind == "class" ? (name, line.indent) : nil
            types.append((name, r, kind == "extension"))
        }

        func finish(folder: URL) -> [String] {
            var files: [String: Text] = [:]
            return types.filter { launchNames.contains($0.name) || (modelNames.contains($0.name) && !$0.isExtension) }.compactMap { type in
                let path = type.range.start.file.hasPrefix("/") ? type.range.start.file : folder.appendingPathComponent(type.range.start.file).path
                guard let text = files[path] ?? Text(path: path) else { return nil }
                files[path] = text
                if modelNames.contains(type.name) {
                    // With its file, which the change must not compile at all: "model Note@Notes.swift: <digest>".
                    let file = path.hasPrefix(folder.standardizedFileURL.path + "/") ? String(path.dropFirst(folder.standardizedFileURL.path.count + 1)) : (path as NSString).lastPathComponent
                    return LiveReload.Group.launch.entry("model " + type.name + "@" + file + ": " + SHA256.hash(data: Data(text.bytes)).prefix(8).map { String(format: "%02x", $0) }.joined())
                }
                guard let start = text.offset(type.range.start), let end = text.tokenEnd(type.range.last) else { return nil }
                let digest = SHA256.hash(data: Data(text.bytes[start..<end])).prefix(8).map { String(format: "%02x", $0) }.joined()
                return LiveReload.Group.launch.entry((type.isExtension ? "extension " : "") + type.name + ": " + digest)
            }
        }
    }

    /// Each constant's starting value, as "\u{2}constant<tab>Type<tab>name: <digest of its text>": what the open app made
    /// is what it keeps, so one whose value changes is rewritten in the live copy to give the new value
    /// (`LiveSlots.fit`). Not part of what a type holds: the layout comparison passes over them.
    static func constantEntries(_ declarations: Declarations) -> [String] {
        startingValues(declarations.constants, declarations, group: .constant, withCalls: true)
            + startingValues(declarations.stored, declarations, group: .stored) + hashEntries(declarations)
    }

    /// Each type's own `hash(into:)`, as "\u{11}hash<tab>Type: <digest of its text>": a set or dictionary the open app
    /// keeps put each value where the old one said, and a lookup by the new one looks elsewhere.
    static func hashEntries(_ declarations: Declarations) -> [String] {
        var files: [String: Text] = [:]
        return declarations.hashing.keys.sorted().compactMap { type in
            guard let r = declarations.hashing[type], let text = files[r.start.file] ?? Text(path: r.start.file) else { return nil }
            files[r.start.file] = text
            guard let start = text.offset(r.start), let end = text.tokenEnd(r.last), start < end else { return nil }
            // With what it calls, as far down as that goes: a hash made with `Config.salt` changes when `salt` does.
            return LiveReload.Group.hash.entry(type + ": " + digest(text.slice(start, end) + "\n" + calledText(from: r.start, to: r.last, in: declarations, files: &files)))
        }
    }

    static func before(_ a: Position, _ b: Position) -> Bool { a.line < b.line || (a.line == b.line && a.column <= b.column) }

    /// The text of every declaration of the app's that a stretch of code calls, and of what those call, as far down
    /// as it goes, in a steady order: a constant made by `build()` is another value once `build()` says otherwise.
    static func calledText(from start: Position, to last: Position, in declarations: Declarations, files: inout [String: Text]) -> String {
        func within(_ p: Position, _ r: (start: Position, last: Position)) -> Bool { p.file == r.start.file && before(r.start, p) && before(p, r.last) }
        var seen: Set<Int> = [], pending = [(start: start, last: last)], parts: [String] = []
        while let r = pending.popLast() {
            for call in declarations.calls where within(call.at, r) {
                // The innermost declaration holding the place it names.
                guard let index = declarations.bodies.indices.filter({ within(call.to, declarations.bodies[$0]) })
                        .min(by: { before(declarations.bodies[$1].start, declarations.bodies[$0].start) }),
                      !seen.contains(index), case let body = declarations.bodies[index], !(body.start == start && body.last == last) else { continue }
                seen.insert(index)
                guard let text = files[body.start.file] ?? Text(path: body.start.file) else { continue }
                files[body.start.file] = text
                guard let from = text.offset(body.start), let end = text.tokenEnd(body.last), from < end else { continue }
                parts.append(text.slice(from, end))
                pending.append(body)
            }
        }
        return parts.sorted().joined(separator: "\n")
    }

    /// Each one's starting value's digest, as an entry of `group`.
    private static func startingValues(_ variables: [String: Variable], _ declarations: Declarations, group: LiveReload.Group,
                                       withCalls: Bool = false) -> [String] {
        var files: [String: Text] = [:]
        return variables.keys.sorted().compactMap { key in
            guard let variable = variables[key],
                  let initial = declarations.bindings[variable.binding].entries.first(where: { $0.name == variable.name })?.initial else { return nil }
            let path = initial.start.file
            guard let text = files[path] ?? Text(path: path) else { return nil }
            files[path] = text
            guard let start = text.offset(initial.start), let end = text.tokenEnd(initial.last), start < end else { return nil }
            // With its type: one whose type changed is another value, kept in other storage by the change's code.
            let own = digest(variable.type + "=" + text.slice(start, end))
            // And for a constant, after a `+`, what it calls: made again, it's another value though its text is the same.
            guard withCalls else { return group.entry(key + ": " + own) }
            let binding = declarations.bindings[variable.binding]
            return group.entry(key + ": " + own + "+" + digest(calledText(from: binding.start, to: binding.last, in: declarations, files: &files)))
        }
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// A file's text as bytes, which the compiler's columns count.
    struct Text {
        var bytes: [UInt8]
        private var lineStarts: [Int]

        init(_ string: String) {
            let all = Array(string.utf8)
            bytes = all
            lineStarts = [0] + all.indices.filter { all[$0] == UInt8(ascii: "\n") }.map { $0 + 1 }
        }

        init?(path: String) {
            guard let string = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            self.init(string)
        }

        var string: String { String(decoding: bytes, as: UTF8.self) }

        func offset(_ position: Position) -> Int? {
            guard position.line >= 1, position.line <= lineStarts.count else { return nil }
            let offset = lineStarts[position.line - 1] + position.column - 1
            return offset <= bytes.count ? offset : nil
        }

        /// Just past the token that starts at `position`: a word or number, a string (of any kind), or one mark.
        func tokenEnd(_ position: Position) -> Int? {
            guard let start = offset(position), start < bytes.count else { return nil }
            let byte = bytes[start]
            func isWord(_ b: UInt8) -> Bool { b >= 0x80 || b == UInt8(ascii: "_") || b == UInt8(ascii: "$") || (b >= 48 && b <= 57) || (b | 0x20 >= 97 && b | 0x20 <= 122) }
            if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "#") {
                let rest = Array(String(decoding: bytes[start...], as: UTF8.self))
                if let end = SwiftText.skip(rest, at: 0) { return start + String(rest[..<end]).utf8.count }
            }
            guard isWord(byte) else { return start + 1 }
            var end = start
            let number = byte >= 48 && byte <= 57
            let hex = number && start + 1 < bytes.count && byte == UInt8(ascii: "0") && bytes[start + 1] | 0x20 == UInt8(ascii: "x")
            while end < bytes.count {
                let b = bytes[end]
                if isWord(b) || (number && b == UInt8(ascii: ".")) { end += 1; continue }
                // A signed exponent is part of the literal: after `e` in a decimal one, after `p` in a hex one.
                if number, end > start, b == UInt8(ascii: "+") || b == UInt8(ascii: "-"),
                   bytes[end - 1] | 0x20 == (hex ? UInt8(ascii: "p") : UInt8(ascii: "e")) { end += 1; continue }
                break
            }
            return end
        }

        func slice(_ from: Int, _ to: Int) -> String { String(decoding: bytes[from..<to], as: UTF8.self) }
    }
}

// MARK: - One pass over a printout

extension SwiftSource {
    /// One pass over a printout with the scopes kept in one place: which type, extension, protocol or function each
    /// line is inside, and how a type is keyed (qualified by what it's nested in, with its file when it's private,
    /// with its function when it's declared inside one). Every reader of a printout goes through it (`members`,
    /// `declarations`, `launchEntries`, `oldCodeUses`), so they key a type alike and the printout is read once.
    enum Walk {
        /// A type a line opens, as the layout keys it and as the compiler prints it.
        struct TypeDecl {
            /// Nested types under their outer type's key, a private one with its file (`Row@A.swift`), one declared
            /// inside a function with the function (`Shelf.pick().Answer`): the key every reader uses.
            var key: String
            var kind: String
            var access: String
            var file: String?
            var isPrivate: Bool
            /// Its generic parameters (`T, U`), when it has any.
            var parameters: String?
            /// Generic itself, or declared inside a generic type: laid out afresh for each type it's used at.
            var isGeneric: Bool
            /// What it inherits or conforms to, as printed (`inherits="A, P"`).
            var inherits: String?
            var range: (start: Position, last: Position)?
        }
        enum Scope {
            case type(TypeDecl)
            case extensionOf(String)
            case protocolDecl(String)
            /// A function, initializer, accessor, closure, subscript or top-level code, by `scopeName`.
            case function(String)
        }
        /// A line that opens a node, with where it sits. `text` is made only when a reader asks for it.
        final class Line {
            let raw: Substring
            let node: Node
            var indent: Int { node.indent }
            lazy var text: String = String(raw)
            lazy var range: NSRange = NSRange(text.startIndex..., in: text)
            /// The scopes around this line, outermost first.
            let scopes: [(indent: Int, scope: Scope)]
            /// What a member on this line belongs to: the nearest scope when that's a type (its key), an extension
            /// (its type's name) or a protocol ("protocol Name"); nil inside a function, where it's a local.
            let owner: String?
            var isTopLevel: Bool { scopes.isEmpty }
            /// What this line opens, when it opens one of these.
            let type: TypeDecl?
            let extensionOf: String?
            let protocolName: String?
            let function: String?
            init(raw: Substring, node: Node, scopes: [(indent: Int, scope: Scope)], owner: String?, type: TypeDecl?, extensionOf: String?, protocolName: String?, function: String?) {
                self.raw = raw; self.node = node; self.scopes = scopes; self.owner = owner
                self.type = type; self.extensionOf = extensionOf; self.protocolName = protocolName; self.function = function
            }
            func opens(_ names: String...) -> Bool { names.contains { node.name.utf8.starts(with: $0.utf8) } }
            func has(_ text: String) -> Bool { SwiftSource.has(self.text, text) }
        }

        /// The names of the app's own classes and protocols, read before the pass: the first name a class inherits is
        /// its superclass when it's one of these classes, and isn't when it's one of these protocols (the layout reader
        /// asks the class's initializers about anything else).
        struct Names {
            var classes = Set<String>(), protocols = Set<String>()
        }
    }

    private static let walkTypeDecl = try! NSRegularExpression(pattern: #"^(\s*)\((struct|class|enum|actor)_decl\b[^"]*"([^"]+)".*? access=(\w+)"#)
    private static let walkGenericDecl = try! NSRegularExpression(pattern: #"^\s*\(\w+_decl\b[^"]*"[^"]+" "<([^"]*)>""#)
    private static let walkInherits = try! NSRegularExpression(pattern: #" inherits="([^"]*)""#)
    private static let walkExtensionDecl = try! NSRegularExpression(pattern: #"^(\s*)\(extension_decl\b[^"]*"([^"]+)""#)
    private static let walkProtocolDecl = try! NSRegularExpression(pattern: #"^(\s*)\(protocol(_decl)?\b[^"]*"([^"]+)""#)
    private static let walkClassName = try! NSRegularExpression(pattern: #"^\s*\(class_decl\b[^"]*"([^"]+)""#)

    /// The app's own class and protocol names, from the printout's declaration lines.
    static func names(inDump dump: String) -> Walk.Names {
        var names = Walk.Names()
        for raw in lines(dump) {
            guard let node = node(raw), node.opens("class_decl", "protocol") else { continue }
            let line = String(raw), range = NSRange(line.startIndex..., in: line)
            if node.opens("class_decl"), let m = walkClassName.firstMatch(in: line, range: range) { names.classes.insert(String(line[Range(m.range(at: 1), in: line)!])) }
            if node.opens("protocol"), let m = walkProtocolDecl.firstMatch(in: line, range: range) { names.protocols.insert(String(line[Range(m.range(at: 3), in: line)!])) }
        }
        return names
    }

    /// Walks the printout once, giving each line that opens a node to `visit` with the scopes around it.
    static func walk(_ dump: String, _ visit: (Walk.Line) -> Void) {
        var scopes: [(indent: Int, scope: Walk.Scope)] = []
        for raw in lines(dump) {
            // Only a line that opens a node says where it sits; the closing brackets of a deep node sometimes come on
            // a line of their own at the left edge, which would otherwise end every scope.
            guard let node = node(raw) else { continue }
            let indent = node.indent
            while let last = scopes.last, last.indent >= indent { scopes.removeLast() }
            var type: Walk.TypeDecl?, extensionOf: String?, protocolName: String?, function: String?
            lazy var text = String(raw)
            lazy var range = NSRange(text.startIndex..., in: text)
            if node.opens("struct_decl", "class_decl", "enum_decl", "actor_decl"), let m = walkTypeDecl.firstMatch(in: text, range: range) {
                var name = String(text[Range(m.range(at: 3), in: text)!])
                // The nearest type around it, and the functions between it and here: a local type is keyed with
                // them all (`Shelf.pick().first().Answer`), since two functions may each declare a local type of
                // one name, nested ones included.
                var outer: String?, inFunctions: [String] = []
                for (_, scope) in scopes {
                    switch scope {
                    case .type(let t): outer = t.key; inFunctions = []
                    case .extensionOf(let n): outer = n; inFunctions = []
                    case .protocolDecl(let n): outer = "protocol " + n; inFunctions = []
                    case .function(let n): inFunctions.append(n)
                    }
                }
                if !inFunctions.isEmpty { name = inFunctions.joined(separator: ".") + "." + name }
                let access = String(text[Range(m.range(at: 4), in: text)!])
                let place = self.range(in: text)
                let file = place.map { ($0.start.file as NSString).lastPathComponent }
                let isPrivate = ["private", "fileprivate"].contains(access)
                // A private type is keyed with its file: another file may declare one of the same name, and the two
                // are two types, each with its own fields (`LiveReload.bare` gives the name back).
                if isPrivate, let file { name += "@" + file }
                let parameters = walkGenericDecl.firstMatch(in: text, range: range).map { String(text[Range($0.range(at: 1), in: text)!]) }
                let genericContext = scopes.contains { if case .type(let t) = $0.scope { return t.isGeneric } else { return false } }
                type = Walk.TypeDecl(key: outer.map { $0 + "." + name } ?? name, kind: String(text[Range(m.range(at: 2), in: text)!]), access: access,
                                     file: file, isPrivate: isPrivate, parameters: parameters, isGeneric: parameters != nil || genericContext,
                                     inherits: walkInherits.firstMatch(in: text, range: range).map { String(text[Range($0.range(at: 1), in: text)!]) }, range: place)
            } else if node.opens("extension_decl"), let m = walkExtensionDecl.firstMatch(in: text, range: range) {
                extensionOf = String(text[Range(m.range(at: 2), in: text)!])
            } else if node.opens("protocol"), let m = walkProtocolDecl.firstMatch(in: text, range: range) {
                protocolName = String(text[Range(m.range(at: 3), in: text)!])
            } else if node.opens("func_decl", "accessor_decl", "constructor_decl", "destructor_decl", "closure_expr", "subscript_decl", "top_level_code_decl") {
                function = scopeName(text)
            }
            let owner: String?
            switch scopes.last?.scope {
            case .type(let t): owner = t.key
            case .extensionOf(let n): owner = n
            case .protocolDecl(let n): owner = "protocol " + n
            case .function, nil: owner = nil
            }
            let line = Walk.Line(raw: raw, node: node, scopes: scopes, owner: owner, type: type, extensionOf: extensionOf, protocolName: protocolName, function: function)
            visit(line)
            if let type { scopes.append((indent, .type(type))) }
            else if let extensionOf { scopes.append((indent, .extensionOf(extensionOf))) }
            else if let protocolName { scopes.append((indent, .protocolDecl(protocolName))) }
            else if let function { scopes.append((indent, .function(function))) }
        }
    }
}

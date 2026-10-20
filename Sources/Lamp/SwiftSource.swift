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
        /// The app's own classes, whose objects a constant may hold.
        var classes: Set<String> = []
        /// Each type's memberwise initializers that the compiler made itself and code outside the type can call: their
        /// labels and parameter types in order (`init(a:c:)`, `[Int, [Int]?]`). What a struct's code calls to make one.
        var memberwise: [String: [(labels: [String], types: [String])]] = [:]
        /// Each type's initializers written in its code, its extensions' included: labels and parameter types, as
        /// `memberwise` has them, so one can be told from another with the same labels and other types.
        var initializers: [String: [(labels: [String], types: [String])]] = [:]
        /// Where each type's own declaration runs, by its qualified name: what a view's `$name` means is its own.
        var types: [String: (start: Position, last: Position)] = [:]
        /// The types private to their file, which an extension in another file can't reach.
        var privateTypes: Set<String> = []
        /// The stored properties declared with `let` ("Type<tab>name").
        var lets: Set<String> = []
        /// The properties set in an initializer the type writes itself ("Type<tab>name"): a computed property kept
        /// in a spare can't be set before the stored ones are, so such a property stays stored.
        var assigned: Set<String> = []
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

    private static func range(in line: String) -> (start: Position, last: Position)? {
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
        let typeDecl = try! NSRegularExpression(pattern: #"^(\s*)\((struct|class|enum|actor|extension)_decl\b[^"]*"([^"]+)""#)
        let scopeDecl = try! NSRegularExpression(pattern: #"^(\s*)\((func_decl|accessor_decl|constructor_decl|destructor_decl|closure_expr|subscript_decl|top_level_code_decl)\b"#)
        let varDecl = try! NSRegularExpression(pattern: #"^(\s*)\(var_decl\b[^"]*"([^"]+)" interface_type="([^"]*)"(.*)$"#)
        let named = try! NSRegularExpression(pattern: #"\(pattern_named\b.*"([^"]+)"\)*\s*$"#)
        let identifier = try! NSRegularExpression(pattern: #"id="(\w+)""#)
        // An observer's accessor, with the property it's for: under @Observable the macro moves a property's
        // didSet to its `_name` storage in a buffer of its own, and @Published folds it into the wrapper's setter, so
        // the property's own line no longer says it has observers.
        let observer = try! NSRegularExpression(pattern: #"^\s*\(accessor_decl\b.*? (?:didSet|willSet) for="(\w+)""#)
        var observed = Set<String>()
        // An assignment in an initializer the type writes: the node under it says what's set.
        let assigned = try! NSRegularExpression(pattern: #"^(\s*)\(member_ref_expr\b.*? decl="[^"]*?\.(\w+)@"#)
        var out = Declarations()
        var scopes: [(indent: Int, type: String?)] = []
        // The functions, accessors and closures open at this line, by name, as `LiveReload.members` keys a type
        // declared inside one (`Shelf.pick().Answer`).
        var functions: [(indent: Int, name: String)] = []
        // The initializer being read, and an assignment in it whose target is the next node.
        var initializer: (indent: Int, owner: String)?, assignment: Int?
        // The binding being read, at its indent, and what's inside it.
        var binding: (indent: Int, index: Int)?
        var entryOpen = false
        var variable: (indent: Int, key: String)?
        var attribute: (start: Position, last: Position)?
        for raw in lines(dump) {
            guard let node = self.node(raw) else { continue }
            let indent = node.indent, opens = node.opens
            // Made only for a line a pattern is tried on.
            lazy var line = String(raw)
            lazy var range = NSRange(line.startIndex..., in: line)
            if let open = binding, indent <= open.indent { binding = nil }
            if let open = variable, indent <= open.indent { variable = nil; attribute = nil }
            if let open = initializer, indent <= open.indent { initializer = nil; assignment = nil }
            if let open = initializer {
                if let at = assignment {
                    if indent == at + 2, opens("member_ref_expr"), let m = assigned.firstMatch(in: line, range: range) { out.assigned.insert(open.owner + "\t" + String(line[Range(m.range(at: 2), in: line)!])) }
                    assignment = nil
                }
                if opens("assign_expr") { assignment = indent }
                continue
            }
            while let last = scopes.last, last.indent >= indent { scopes.removeLast() }
            while let last = functions.last, last.indent >= indent { functions.removeLast() }
            let owner = scopes.last?.type
            if opens("struct_decl", "class_decl", "enum_decl", "actor_decl", "extension_decl"), let m = typeDecl.firstMatch(in: line, range: range) {
                var name = String(line[Range(m.range(at: 3), in: line)!])
                let outer = scopes.compactMap(\.type).last
                if let local = functions.last, local.indent > (scopes.last { $0.type != nil }?.indent ?? -1) { name = local.name + "." + name }
                let kind = line[Range(m.range(at: 2), in: line)!]
                let isPrivate = kind != "extension" && (has(line, " access=private") || has(line, " access=fileprivate"))
                // A private type is keyed with its file, as the layout keys it (`LiveReload.bare`).
                if isPrivate, let r = self.range(in: line) { name += "@" + (r.start.file as NSString).lastPathComponent }
                let full = outer.map { $0 + "." + name } ?? name
                scopes.append((indent, full))
                if kind == "class" { out.classes.insert(full); out.classes.insert(LiveReload.bare(name)) }
                if kind != "extension", let r = self.range(in: line) { out.types[full] = r }
                if isPrivate { out.privateTypes.insert(full) }
                continue
            }
            if let owner, opens("accessor_decl"), let m = observer.firstMatch(in: line, range: range) {
                var name = String(line[Range(m.range(at: 1), in: line)!])
                if name.hasPrefix("_") { name.removeFirst() }
                observed.insert(owner + "\t" + name)
            }
            if opens("func_decl", "accessor_decl", "constructor_decl", "destructor_decl", "closure_expr", "subscript_decl", "top_level_code_decl"),
               scopeDecl.firstMatch(in: line, range: range) != nil {
                // A convenience initializer sets properties only after `self.init`, when a computed one can be set.
                if let owner, line.contains("(constructor_decl"), !line.contains(" implicit ") {
                    if !has(line, " convenience") { initializer = (indent, owner) }
                    if let made = memberwise(in: line) { out.initializers[owner, default: []].append(made) }
                }
                if let owner, line.contains("(constructor_decl"), line.contains(" implicit "),
                   !line.contains("access=private"), !line.contains("access=fileprivate"),
                   let made = memberwise(in: line), !made.labels.isEmpty {
                    out.memberwise[owner, default: []].append(made)
                }
                scopes.append((indent, nil))
                functions.append((indent, scopeName(line)))
                continue
            }
            if let open = binding {
                // Inside a binding: its entries, each with its name and its starting value.
                if has(line, "(pattern_entry") { out.bindings[open.index].entries.append(Entry(name: "", initial: nil)); entryOpen = true; continue }
                if entryOpen, var entry = out.bindings[open.index].entries.last {
                    if entry.name.isEmpty, has(line, "(pattern_named"), let m = named.firstMatch(in: line, range: range) {
                        entry.name = String(line[Range(m.range(at: 1), in: line)!])
                    } else if entry.initial == nil, has(line, "(original_init=") || has(line, "(processed_init="),
                              let r = self.range(in: line) {
                        // As written, or (when that's unresolved and has no place) as the compiler settled it.
                        entry.initial = r
                    }
                    out.bindings[open.index].entries[out.bindings[open.index].entries.count - 1] = entry
                }
                continue
            }
            if let open = variable {
                // Inside a property: its attributes, each a range followed by the name it uses.
                if has(line, "(reference_ownership_attr") { out.variables[open.key]?.special = true; continue }
                if has(line, "(custom_attr"), let r = self.range(in: line) { attribute = r; continue }
                if let r = attribute, has(line, "id=\""), let m = identifier.firstMatch(in: line, range: range) {
                    out.variables[open.key]?.attributes.append((r.start, r.last, String(line[Range(m.range(at: 1), in: line)!])))
                    attribute = nil
                }
                continue
            }
            // A type's members, and the file's own globals.
            let global = scopes.isEmpty
            guard owner != nil || global else { continue }
            if has(line, "(pattern_binding_decl"), let r = self.range(in: line) {
                out.bindings.append(Binding(start: r.start, last: r.last, entries: []))
                binding = (indent, out.bindings.count - 1)
                entryOpen = false
                continue
            }
            if opens("var_decl"), let m = varDecl.firstMatch(in: line, range: range), let r = self.range(in: line), let index = out.bindings.indices.last {
                let name = String(line[Range(m.range(at: 2), in: line)!])
                guard out.bindings[index].entries.contains(where: { $0.name == name }) else { continue }
                let isStatic = line.contains(" static"), rest = String(line[Range(m.range(at: 4), in: line)!])
                if isStatic || global {
                    // A constant: a static or global `let` with a starting value.
                    if rest.contains(" let ") {
                        // A private or file-private one is the file's own: another file may have one by the same name.
                        let own = rest.contains("access=private") || rest.contains("access=fileprivate")
                        let place = own ? "@" + (r.start.file as NSString).lastPathComponent : ""
                        out.constants[(owner ?? "") + "\t" + name + place] = Variable(name: name, position: r.start,
                                                                               type: String(line[Range(m.range(at: 3), in: line)!]),
                                                                               binding: index, attributes: [])
                    }
                    continue
                }
                guard let owner else { continue }
                let key = owner + "\t" + name
                out.variables[key] = Variable(name: name, position: r.start, type: String(line[Range(m.range(at: 3), in: line)!]),
                                              binding: index, attributes: [],
                                              special: rest.contains("with_observers") || rest.contains(" lazy "))
                if rest.contains(" let ") { out.lets.insert(key) }
                variable = (indent, key)
            }
        }
        for key in observed { out.variables[key]?.special = true }
        return out
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
    private static func memberwise(in line: String) -> (labels: [String], types: [String])? {
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
    /// app's container doesn't know, so any change to that file reopens the app.
    static func launchEntries(inDump dump: String, folder: URL) -> [String] {
        let decl = try! NSRegularExpression(pattern: #"^(\s*)\((struct|class|enum|extension)_decl\b[^"]*"([^"]+)"(.*)$"#)
        let launch = try! NSRegularExpression(pattern: #"inherits="[^"]*\b(App|Scene|Commands|NSApplicationDelegate|UIApplicationDelegate)\b"#)
        let model = try! NSRegularExpression(pattern: #"^(\s*)\(custom_attr\b.*macro="SwiftData\.\(file\)\.Model\(\)""#)
        var types: [(name: String, range: (start: Position, last: Position), isExtension: Bool)] = []
        var launchNames = Set<String>(), modelNames = Set<String>()
        var lastClass: (name: String, indent: Int)?
        for raw in lines(dump) {
            guard let node = self.node(raw) else { continue }
            lazy var line = String(raw)
            lazy var whole = NSRange(line.startIndex..., in: line)
            if let last = lastClass, node.opens("custom_attr"), let m = model.firstMatch(in: line, range: whole), m.range(at: 1).length == last.indent + 2 {
                modelNames.insert(last.name)
            }
            guard node.opens("struct_decl", "class_decl", "enum_decl", "extension_decl"),
                  let m = decl.firstMatch(in: line, range: whole), let r = range(in: line) else { continue }
            let name = String(line[Range(m.range(at: 3), in: line)!])
            let kind = line[Range(m.range(at: 2), in: line)!]
            // A conformance may be declared on the type or on an extension of it (`extension Demo: App`).
            if launch.firstMatch(in: line, range: whole) != nil { launchNames.insert(name) }
            lastClass = kind == "class" ? (name, m.range(at: 1).length) : nil
            types.append((name, r, kind == "extension"))
        }
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

    /// Each constant's starting value, as "\u{2}constant<tab>Type<tab>name: <digest of its text>": what the open app made
    /// is what it keeps, so one whose value changes is rewritten in the live copy to give the new value
    /// (`LiveSlots.fit`). Not part of what a type holds: the layout comparison passes over them.
    static func constantEntries(_ declarations: Declarations) -> [String] {
        var files: [String: Text] = [:]
        return declarations.constants.keys.sorted().compactMap { key in
            guard let variable = declarations.constants[key],
                  let initial = declarations.bindings[variable.binding].entries.first(where: { $0.name == variable.name })?.initial else { return nil }
            let path = initial.start.file
            guard let text = files[path] ?? Text(path: path) else { return nil }
            files[path] = text
            guard let start = text.offset(initial.start), let end = text.tokenEnd(initial.last), start < end else { return nil }
            return LiveReload.Group.constant.entry(key + ": " + digest(text.slice(start, end)))
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

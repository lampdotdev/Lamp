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
        var out = Declarations()
        var scopes: [(indent: Int, type: String?)] = []
        // The binding being read, at its indent, and what's inside it.
        var binding: (indent: Int, index: Int)?
        var entryOpen = false
        var variable: (indent: Int, key: String)?
        var attribute: (start: Position, last: Position)?
        let lines = dump.components(separatedBy: "\n")
        for line in lines {
            let indent = line.prefix { $0 == " " }.count
            guard line.dropFirst(indent).first == "(" else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if let open = binding, indent <= open.indent { binding = nil }
            if let open = variable, indent <= open.indent { variable = nil; attribute = nil }
            while let last = scopes.last, last.indent >= indent { scopes.removeLast() }
            let owner = scopes.last?.type
            if let m = typeDecl.firstMatch(in: line, range: range) {
                let name = String(line[Range(m.range(at: 3), in: line)!])
                let outer = scopes.compactMap(\.type).last
                let full = outer.map { $0 + "." + name } ?? name
                scopes.append((indent, full))
                if line[Range(m.range(at: 2), in: line)!] == "class" { out.classes.insert(full); out.classes.insert(name) }
                continue
            }
            if scopeDecl.firstMatch(in: line, range: range) != nil { scopes.append((indent, nil)); continue }
            if let open = binding {
                // Inside a binding: its entries, each with its name and its starting value.
                if line.contains("(pattern_entry") { out.bindings[open.index].entries.append(Entry(name: "", initial: nil)); entryOpen = true; continue }
                if entryOpen, var entry = out.bindings[open.index].entries.last {
                    if entry.name.isEmpty, let m = named.firstMatch(in: line, range: range) {
                        entry.name = String(line[Range(m.range(at: 1), in: line)!])
                    } else if entry.initial == nil, line.contains("(original_init=") || line.contains("(processed_init="),
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
                if line.contains("(reference_ownership_attr") { out.variables[open.key]?.special = true; continue }
                if line.contains("(custom_attr"), let r = self.range(in: line) { attribute = r; continue }
                if let r = attribute, let m = identifier.firstMatch(in: line, range: range) {
                    out.variables[open.key]?.attributes.append((r.start, r.last, String(line[Range(m.range(at: 1), in: line)!])))
                    attribute = nil
                }
                continue
            }
            // A type's members, and the file's own globals.
            let global = scopes.isEmpty
            guard owner != nil || global else { continue }
            if line.contains("(pattern_binding_decl"), let r = self.range(in: line) {
                out.bindings.append(Binding(start: r.start, last: r.last, entries: []))
                binding = (indent, out.bindings.count - 1)
                entryOpen = false
                continue
            }
            if let m = varDecl.firstMatch(in: line, range: range), let r = self.range(in: line), let index = out.bindings.indices.last {
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
                variable = (indent, key)
            }
        }
        return out
    }

    /// The types SwiftUI or AppKit read only at launch, at any depth: the App, its scenes, its menu commands and
    /// an application delegate, with extensions of them. Each is "\u{1}launch<tab>Name: <digest of its text>",
    /// entries the layout comparison holds to what the open app had, so a change to one reopens the app.
    static func launchEntries(inDump dump: String, folder: URL) -> [String] {
        let decl = try! NSRegularExpression(pattern: #"^\s*\((struct|class|enum|extension)_decl\b[^"]*"([^"]+)"(.*)$"#)
        let launch = try! NSRegularExpression(pattern: #"inherits="[^"]*\b(App|Scene|Commands|NSApplicationDelegate|UIApplicationDelegate)\b"#)
        var types: [(name: String, range: (start: Position, last: Position), isExtension: Bool)] = []
        var launchNames = Set<String>()
        for line in dump.components(separatedBy: "\n") {
            let whole = NSRange(line.startIndex..., in: line)
            guard let m = decl.firstMatch(in: line, range: whole), let r = range(in: line) else { continue }
            let name = String(line[Range(m.range(at: 2), in: line)!])
            let isExtension = line[Range(m.range(at: 1), in: line)!] == "extension"
            // A conformance may be declared on the type or on an extension of it (`extension Demo: App`).
            if launch.firstMatch(in: line, range: whole) != nil { launchNames.insert(name) }
            types.append((name, r, isExtension))
        }
        var files: [String: Text] = [:]
        return types.filter { launchNames.contains($0.name) }.compactMap { type in
            let path = type.range.start.file.hasPrefix("/") ? type.range.start.file : folder.appendingPathComponent(type.range.start.file).path
            guard let text = files[path] ?? Text(path: path) else { return nil }
            files[path] = text
            guard let start = text.offset(type.range.start), let end = text.tokenEnd(type.range.last) else { return nil }
            let digest = SHA256.hash(data: Data(text.bytes[start..<end])).prefix(8).map { String(format: "%02x", $0) }.joined()
            return "\u{1}launch\t" + (type.isExtension ? "extension " : "") + type.name + ": " + digest
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
            return "\u{2}constant\t" + key + ": " + digest(text.slice(start, end))
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
            while end < bytes.count, isWord(bytes[end]) || (number && bytes[end] == UInt8(ascii: ".")) { end += 1 }
            return end
        }

        func slice(_ from: Int, _ to: Int) -> String { String(decoding: bytes[from..<to], as: UTF8.self) }
    }
}

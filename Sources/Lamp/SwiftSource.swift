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
        /// Stored static and global `var`s with a starting value, and lazy properties, keyed the same: the open app made
        /// each once (a lazy one once for each object) and keeps it, so a new starting value can't show without reopening.
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
        /// Every use of the app's own declarations, where it's made and what it names, as the compiler resolved it:
        /// its qualified name (`Mood.happy`, `Model.$count`), or for a type written out (the `Mood` of
        /// `Mood.allCases`, `[Mood]`), that type's name. What code names is read from here, never from its text, so a
        /// string, a comment or a local of the same name is no use of it.
        var uses: [(at: Position, name: String)] = []
        /// Where each escaping closure that returns nothing runs (an action, a handler: `.onAppear { … }`, a Button's):
        /// code in one runs when it's called, not each time a body is drawn, nor where it's written. One that doesn't
        /// escape (`withAnimation { … }`, `MainActor.assumeIsolated { … }`) runs there and then.
        var actions: [(start: Position, last: Position)] = []
        /// The uses that are a key path's components (`\.$count`), which have no place of their own: in `uses` at the
        /// key path's start, and here with the key path's whole span, where the token is.
        var keyPathUses: [(start: Position, last: Position, name: String)] = []
        /// Where each enum's cases are declared, with their raw values: what a use of a case is made of.
        var cases: [(start: Position, last: Position)] = []
        /// Each type's own `hash(into:)`, by its qualified name: sets and dictionaries the open app keeps were laid out
        /// by it (`hashEntries`).
        var hashing: [String: (start: Position, last: Position)] = [:]
        /// The names of the app's own typealiases, which may stand for a system type's name (`typealias Color = Paint`).
        var aliases: Set<String> = []
        /// What each type name written in the app's code is, by the compiler's own resolution of it (`bind="…"`): a
        /// system declaration by its module and name (`Font.Design` is `SwiftUICore.Font.Design`), or "" when the same
        /// name was resolved to more than one. A name the app declares itself, wherever (a typealias in the widget's
        /// shared code, a private type in another file), is in `ownResolved` instead.
        var systemResolved: [String: String] = [:]
        var ownResolved: Set<String> = []
        /// Whether the app's code gives views a defaults store of its own (`.defaultAppStorage(…)`), which an
        /// `@AppStorage` without one reads from: where that is, Lamp can't say.
        var choosesDefaultStore = false

        /// Whether code in `ranges` names the type (its qualified name, as `bare` gives it): uses it as a type, or
        /// uses one of its members. One of the `cases` alone (`.a`) is no use of the type as a whole: what's made
        /// from it is the same however many cases there are.
        func names(type: String, within ranges: [(start: Position, last: Position)], except cases: Set<String> = []) -> Bool {
            let short = String(type.split(separator: ".").last ?? "")
            return uses.contains { use in
                guard ranges.contains(where: { SwiftSource.within(use.at, $0) }) else { return false }
                if use.name == type || use.name == short || use.name.hasSuffix("." + short) { return true }
                guard use.name.hasPrefix(type + ".") else { return false }
                return !cases.contains(String(use.name.dropFirst(type.count + 1).prefix { $0 != "(" }))
            }
        }

        /// Whether code in `ranges` uses what's declared at `position` (a constant, by its name's place).
        func uses(_ position: Position, within ranges: [(start: Position, last: Position)]) -> Bool {
            calls.contains { call in call.to == position && ranges.contains { SwiftSource.within(call.at, $0) } }
        }

        /// Every name the app gives a type of its own, by its last part: the system's type of that name isn't what
        /// the app's code means by it.
        var ownTypeNames: Set<String> {
            Set(types.keys.map { String(LiveReload.bare($0).split(separator: ".").last ?? "") }).union(aliases)
        }
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
              case var value = line[open.upperBound..<close] else { return nil }
        // A generic one's substitutions follow its place (`@A.swift:3:6 [with (substitution_map …)]`).
        if let with = value.range(of: " [with") { value = value[..<with.lowerBound] }
        guard let at = value.lastIndex(of: "@") else { return nil }
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
        /// One `bind="…"`: the app's own declaration carries its place (`App.(file).Order@Shared.swift:2:11`), a
        /// system one doesn't (`SwiftUICore.(file).Font extension.Design`).
        private func resolved(_ value: Substring) {
            var text = value
            if let with = text.range(of: " [with") { text = text[..<with.lowerBound] }
            guard let file = text.range(of: ".(file).") else { return }
            let name = text[file.upperBound...].replacingOccurrences(of: " extension", with: "")
            if let at = name.firstIndex(of: "@") { out.ownResolved.insert(String(name[..<at])); return }
            let qualified = text[..<file.lowerBound] + "." + name
            out.systemResolved[name] = out.systemResolved[name].map { $0 == qualified ? $0 : "" } ?? qualified
        }

        private let varDecl = try! NSRegularExpression(pattern: #"^(\s*)\(var_decl\b[^"]*"([^"]+)" interface_type="([^"]*)"(.*)$"#)
        private let named = try! NSRegularExpression(pattern: #"\(pattern_named\b.*"([^"]+)"\)*\s*$"#)
        private let identifier = try! NSRegularExpression(pattern: #"id="(\w+)""#)
        // An observer's accessor, with the property it's for: under @Observable the macro moves a property's
        // didSet to its `_name` storage in a buffer of its own, and @Published folds it into the wrapper's setter, so
        // the property's own line no longer says it has observers.
        private let observer = try! NSRegularExpression(pattern: #"^\s*\(accessor_decl\b.*? (?:didSet|willSet) for="(\w+)""#)
        // An assignment in an initializer the type writes: the node under it says what's set.
        private let assigned = try! NSRegularExpression(pattern: #"^(\s*)\(member_ref_expr\b.*? decl="[^"]*?\.(\w+)@"#)
        private let aliasName = try! NSRegularExpression(pattern: #"^\s*\(typealias\b[^"]*"(\w+)""#)
        private var observed = Set<String>()
        private var out = Declarations()
        // The initializer being read, and an assignment in it whose target is the next node.
        private var initializer: (indent: Int, owner: String)?, assignment: Int?
        // The binding being read, at its indent, and what's inside it.
        private var binding: (indent: Int, index: Int)?
        private var entryOpen = false
        private var variable: (indent: Int, key: String)?
        private var attribute: (start: Position, last: Position)?
        // The indent of a freestanding macro being read (`#Preview`), whose code is skipped.
        private var preview: Int?
        // Where the last node read with a place starts: a type annotation's line has none.
        private var lastAt: Position?
        // The key path being read, whose components have no place of their own.
        private var keyPath: (indent: Int, range: (start: Position, last: Position))?

        /// An attribute's quoted value on a line (`decl="…"`).
        static func attribute(_ name: String, in line: String) -> Substring? {
            guard let open = line.range(of: " \(name)=\"") else { return nil }
            let rest = line[open.upperBound...]
            return rest.firstIndex(of: "\"").map { rest[..<$0] }
        }

        func take(_ line: Walk.Line) {
            let indent = line.indent, opens = line.opens
            // A freestanding macro's code (`#Preview { … }`) never runs in the app: nothing in it is a use of anything.
            if let open = preview, indent > open { return }
            // And the type such a macro writes for it, named by its mangled name (`$s…PreviewRegistryfMu_`).
            preview = opens("macro_expansion_decl") || opens("struct_decl") && line.has(" \"$s") ? indent : nil
            if line.has("extension.defaultAppStorage") { out.choosesDefaultStore = true }
            if opens("typealias"), let m = aliasName.firstMatch(in: line.text, range: line.range) {
                out.aliases.insert(String(line.text[Range(m.range(at: 1), in: line.text)!]))
            }
            if opens("func_decl", "constructor_decl", "subscript_decl", "pattern_binding_decl"), !line.has(" implicit"),
               let r = SwiftSource.range(in: line.text) {
                lastAt = r.start
                out.bodies.append(r)
                if opens("func_decl"), line.has(" \"hash(into:)\" "), let owner = line.owner { out.hashing[owner] = r }
            } else if opens("enum_case_decl"), let r = SwiftSource.range(in: line.text) {
                out.cases.append(r)
            } else if opens("closure_expr", "autoclosure_expr"), line.has("-> ()\"") || line.has("-> Void\""), line.has(" escaping"), let r = SwiftSource.range(in: line.text) {
                // (A method passed as a value, `Button("Refresh", action: refresh)`, is one the compiler writes.)
                out.actions.append(r)
            } else if line.has(" decl=\""), let at = SwiftSource.range(in: line.text)?.start {
                lastAt = at
                if let to = SwiftSource.declared(in: line.text) { out.calls.append((at, to)) }
                if let value = Self.attribute("decl", in: line.text), let name = SwiftSource.usedName(value) {
                    out.uses.append((SwiftSource.location(in: line.text) ?? at, name))
                }
            } else if opens("member"), line.has(" decl=\""), let path = keyPath, indent > path.indent {
                // A key path's component (`\.$count`) has no place of its own: it's at the key path's, and its token
                // is found within that.
                if let to = SwiftSource.declared(in: line.text) { out.calls.append((path.range.start, to)) }
                if let value = Self.attribute("decl", in: line.text), let name = SwiftSource.usedName(value) {
                    out.uses.append((path.range.start, name))
                    out.keyPathUses.append((path.range.start, path.range.last, name))
                }
            }
            if let open = keyPath, indent <= open.indent, !opens("member") { keyPath = nil }
            if line.has("keypath_expr type="), !line.has("keypath_application_expr"), let r = SwiftSource.range(in: line.text) {
                keyPath = (indent, r)
            }
            // A type written out: as an expression (`Mood.allCases`), or in an annotation, whose line has no place of
            // its own and is taken to be where the declaration around it starts.
            // (Not one the compiler supplied: `.a`'s base is `Mood`, written nowhere.)
            if line.has(" bind=\""), let value = Self.attribute("bind", in: line.text) { resolved(value) }
            if line.has(" typerepr=\""), !line.has(" implicit "), let value = Self.attribute("typerepr", in: line.text),
               let at = SwiftSource.location(in: line.text) ?? lastAt {
                for word in value.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }) where !word.isEmpty {
                    out.uses.append((at, String(word)))
                }
            } else if line.has(" bind=\""), let value = Self.attribute("bind", in: line.text), let name = SwiftSource.usedName(value), let at = lastAt {
                out.uses.append((at, name))
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
                // Only the binding's own entries: a closure in a starting value declares locals of its own
                // (`{ let formatter = NumberFormatter(); …; return formatter }()`), which are none of its names.
                if opens("pattern_entry"), indent == open.indent + 2 { out.bindings[open.index].entries.append(Entry(name: "", initial: nil)); entryOpen = true; return }
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
                // A lazy property is made once too, by each object the first time it's read: a new starting value would
                // show on some objects and not others.
                if rest.contains(" lazy ") { out.stored[key] = out.variables[key] }
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
            + startingValues(declarations.stored, declarations, group: .stored, withCalls: true) + hashEntries(declarations)
            // An instance's plain properties (and what reads a stored default, `@AppStorage`), whose starting value
            // shows only in an instance made again; not state SwiftUI keeps (`@State`), which keeps its own anyway.
            + startingValues(declarations.variables.filter { $0.value.attributes.allSatisfy { ["AppStorage", "SceneStorage", "Entry"].contains($0.name) } },
                             declarations, group: .defaults, withCalls: true)
            + computedDefaults(declarations)
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

    /// Whether code in `from` reads what's declared in `target`, directly or through the app's code it calls, as far
    /// down as that goes.
    static func reaches(from: [(start: Position, last: Position)], _ target: (start: Position, last: Position), in declarations: Declarations) -> Bool {
        func within(_ p: Position, _ r: (start: Position, last: Position)) -> Bool { p.file == r.start.file && before(r.start, p) && before(p, r.last) }
        var pending = from, seen = Set<Int>()
        while let r = pending.popLast() {
            for call in declarations.calls where within(call.at, r) {
                if within(call.to, target) { return true }
                guard let index = declarations.bodies.indices.filter({ within(call.to, declarations.bodies[$0]) })
                        .min(by: { before(declarations.bodies[$1].start, declarations.bodies[$0].start) }), seen.insert(index).inserted else { continue }
                pending.append(declarations.bodies[index])
            }
        }
        return false
    }

    /// The app's code that code in `from` calls, as far down as that goes: each declaration's body, `from` itself
    /// included, so what's made there can be read off its uses (`Declarations.names`).
    static func reached(from: [(start: Position, last: Position)], in declarations: Declarations) -> [(start: Position, last: Position)] {
        func within(_ p: Position, _ r: (start: Position, last: Position)) -> Bool { p.file == r.start.file && before(r.start, p) && before(p, r.last) }
        var pending = from, seen = Set<Int>(), out = from
        while let r = pending.popLast() {
            for call in declarations.calls where within(call.at, r) {
                guard let index = declarations.bodies.indices.filter({ within(call.to, declarations.bodies[$0]) })
                        .min(by: { before(declarations.bodies[$1].start, declarations.bodies[$0].start) }), seen.insert(index).inserted else { continue }
                pending.append(declarations.bodies[index])
                out.append(declarations.bodies[index])
            }
        }
        return out
    }

    /// A type as Swift's short spellings write it (`Array<String>` is `[String]`, `Optional<Int>` is `Int?`,
    /// `Dictionary<K, V>` is `[K: V]`): the compiler prints a type as the code spells it, and the two are one type.
    static func sugared(_ type: String, except own: Set<String> = []) -> String {
        var text = type
        let rules: [(name: String, pattern: String, write: (String, String) -> String)] = [
            ("Array", #"(?<![\w.])Array<([^<>]*)>"#, { inner, _ in "[\(inner)]" }),
            ("Optional", #"(?<![\w.])Optional<([^<>]*)>"#, { inner, _ in inner.contains(where: { " -&,".contains($0) }) ? "(\(inner))?" : inner + "?" }),
            ("Dictionary", #"(?<![\w.])Dictionary<([^<>,]*), ([^<>]*)>"#, { key, value in "[\(key): \(value)]" }),
        ]
        var changed = true
        while changed {
            changed = false
            // Only Swift's own: a type of the app's by one of these names is another type.
            for (name, pattern, write) in rules where !own.contains(name) {
                guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let whole = Range(m.range, in: text) else { continue }
                let first = String(text[Range(m.range(at: 1), in: text)!])
                let second = m.numberOfRanges > 2 ? Range(m.range(at: 2), in: text).map { String(text[$0]) } ?? "" : ""
                text.replaceSubrange(whole, with: write(first, second))
                changed = true
            }
        }
        return text
    }

    static func before(_ a: Position, _ b: Position) -> Bool { a.line < b.line || (a.line == b.line && a.column <= b.column) }
    static func within(_ p: Position, _ r: (start: Position, last: Position)) -> Bool { p.file == r.start.file && before(r.start, p) && before(p, r.last) }

    /// The qualified name a `decl="…"` or `bind="…"` names, when it's the app's (it carries a place):
    /// `App.(file).Shelf extension.$count@A.swift:3:6 [with …]` is `Shelf.$count`.
    static func usedName(_ value: Substring) -> String? {
        var text = value
        if let with = text.range(of: " [with") { text = text[..<with.lowerBound] }
        // What the compiler wrote has no place, an enum's `allCases` included: that one is recorded all the same,
        // since what's made from it depends on every case (`static let count = allCases.count`, through a typealias).
        if let at = text.range(of: "@") { text = text[..<at.lowerBound] } else if !text.hasSuffix(".allCases") { return nil }
        guard let file = text.range(of: ".(file).") else { return nil }
        return text[file.upperBound...].replacingOccurrences(of: " extension", with: "")
    }

    /// Where a node's own token is (`location=A.swift:4:57`), which a member's range starts before (at its base).
    static func location(in line: String) -> Position? {
        guard let open = line.range(of: " location=") else { return nil }
        let rest = line[open.upperBound...]
        // Up to the attribute after it: a path may hold spaces (`Application Support`).
        let value = rest.range(of: " range=").map { rest[..<$0.lowerBound] } ?? rest.prefix { $0 != " " }
        let parts = value.split(separator: ":")
        guard parts.count >= 3, let row = Int(parts[parts.count - 2]), let column = Int(parts[parts.count - 1]) else { return nil }
        return Position(file: parts.dropLast(2).joined(separator: ":"), line: row, column: column)
    }

    /// The text of every declaration of the app's that a stretch of code calls, and of what those call, as far down
    /// as it goes, in a steady order: a constant made by `build()` is another value once `build()` says otherwise.
    /// `members` follows an initializer and a case into its type's stored properties' starting values and its cases,
    /// for a constant, which Lamp makes again; a stored `var` is state, kept as any object keeps its values.
    static func calledText(from start: Position, to last: Position, in declarations: Declarations, files: inout [String: Text],
                           members followMembers: Bool = false) -> String {
        let ranges = called(from: start, to: last, in: declarations, files: &files, members: followMembers)
        return ranges.compactMap { r -> String? in
            guard let file = files[r.start.file] ?? Text(path: r.start.file) else { return nil }
            files[r.start.file] = file
            guard let from = file.offset(r.start), let end = file.tokenEnd(r.last), from < end else { return nil }
            return file.slice(from, end)
        }.sorted().joined(separator: "\n")
    }

    /// The same declarations, by where each runs: what's asked of them (which types and constants they name) is
    /// asked of the compiler's uses there (`Declarations.names`, `uses`), never of their text.
    static func called(from start: Position, to last: Position, in declarations: Declarations, files: inout [String: Text],
                       members followMembers: Bool = false,
                       skipping: [(start: Position, last: Position)] = []) -> [(start: Position, last: Position)] {
        called(fromAll: [(start, last)], in: declarations, files: &files, members: followMembers, skipping: skipping)
    }

    /// The same from several stretches at once (every view's body), each declaration once however many reach it.
    static func called(fromAll starts: [(start: Position, last: Position)], in declarations: Declarations, files: inout [String: Text],
                       members followMembers: Bool = false,
                       skipping: [(start: Position, last: Position)] = []) -> [(start: Position, last: Position)] {
        func within(_ p: Position, _ r: (start: Position, last: Position)) -> Bool { p.file == r.start.file && before(r.start, p) && before(p, r.last) }
        var seen: Set<Int> = [], pending = starts, parts: [(start: Position, last: Position)] = [], typesSeen = Set<String>()
        func text(_ r: (start: Position, last: Position)) -> String? {
            guard let file = files[r.start.file] ?? Text(path: r.start.file) else { return nil }
            files[r.start.file] = file
            guard let from = file.offset(r.start), let end = file.tokenEnd(r.last), from < end else { return nil }
            return file.slice(from, end)
        }
        // A type's own stored properties' starting values and its cases with their raw values: what an initializer
        // the compiler wrote, one that leaves them as they start, and a case (or its `rawValue`) are made of.
        // Its own: not a local in one of its functions (the bodies are a binding's too, which a member is in).
        let bindingStarts = Set(declarations.bindings.map { "\($0.start.file):\($0.start.line):\($0.start.column)" })
        func members(of type: (start: Position, last: Position)) -> [(start: Position, last: Position)] {
            let inside = declarations.bodies.filter { within($0.start, type) && !bindingStarts.contains("\($0.start.file):\($0.start.line):\($0.start.column)") }
            return (declarations.bindings.map { ($0.start, $0.last) } + declarations.cases)
                .filter { member in within(member.start, type) && !inside.contains { within(member.start, $0) } }
        }
        // Looked up once each: the calls by the file they're made in, and the innermost declaration holding each place
        // a call names.
        let callsIn = Dictionary(grouping: declarations.calls, by: \.at.file)
        var innermost: [Position: Int?] = [:]
        func inner(_ place: Position) -> Int? {
            if let known = innermost[place] { return known }
            let found = declarations.bodies.indices.filter { within(place, declarations.bodies[$0]) }
                .min(by: { before(declarations.bodies[$1].start, declarations.bodies[$0].start) })
            innermost[place] = found
            return found
        }
        let initializer = try! NSRegularExpression(pattern: #"^\s*(?:@\w+\s+|\w+\s+)*init\b"#)
        while let r = pending.popLast() {
            for call in callsIn[r.start.file] ?? [] where within(call.at, r) && !skipping.contains(where: { within(call.at, $0) }) {
                // What it names may be no body of its own (an initializer the compiler wrote, a case) or an
                // initializer: the type around it, by its members.
                let index = inner(call.to)
                if followMembers, index == nil || index.flatMap({ text(declarations.bodies[$0]) }).map({ initializer.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }) == true,
                   let type = declarations.types.filter({ within(call.to, $0.value) }).min(by: { before($1.value.start, $0.value.start) }),
                   typesSeen.insert(type.key).inserted {
                    // And what each member's starting value calls, as far down as that goes (`var audio = Audio()`).
                    for member in members(of: type.value) {
                        parts.append(member)
                        pending.append(member)
                    }
                }
                // The innermost declaration holding the place it names.
                guard let index, !seen.contains(index), case let body = declarations.bodies[index],
                      !starts.contains(where: { body.start == $0.start && body.last == $0.last }) else { continue }
                seen.insert(index)
                parts.append(body)
                pending.append(body)
            }
        }
        return parts
    }

    /// Each one's starting value's digest, as an entry of `group`.
    /// A key's `defaultValue` written as a computed property (`static var defaultValue: String { "light" }`), by its
    /// text: SwiftUI reads it once and keeps it, so a change to it is a starting value changing.
    private static func computedDefaults(_ declarations: Declarations) -> [String] {
        var files: [String: Text] = [:]
        return declarations.bindings.compactMap { binding in
            // Its owner: the type it's declared in, or the type an extension around it extends (`extension ShadeKey:
            // EnvironmentKey { … }`), whichever is innermost.
            let owners = declarations.types.map { ($0.key, $0.value) } + declarations.extensions.flatMap { name, ranges in ranges.map { (name, $0) } }
            guard binding.entries.count == 1, binding.entries[0].name == "defaultValue", binding.entries[0].initial == nil,
                  let owner = owners.filter({ within(binding.start, $0.1) }).min(by: { before($1.1.start, $0.1.start) })?.0,
                  let text = files[binding.start.file] ?? Text(path: binding.start.file) else { return nil }
            files[binding.start.file] = text
            guard let from = text.offset(binding.start), let end = text.tokenEnd(binding.last), from < end else { return nil }
            // With what it calls, as far down as that goes: a getter returning `theme()` changes when `theme()` does.
            let called = calledText(from: binding.start, to: binding.last, in: declarations, files: &files, members: true)
            return LiveReload.Group.defaults.entry(owner + "\tdefaultValue: " + digest(text.slice(from, end)) + "+" + digest(called))
        }
    }

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
            // And after a `+`, what it calls: made again, it's another value though its text is the same.
            // A stored `var` holding one of the app's objects is its state, kept like every other object, whatever made it.
            guard withCalls, group == .constant || !declarations.classes.contains(where: { SwiftText.mentions(identifier: $0, in: variable.type) }) else {
                return group.entry(key + ": " + own)
            }
            let binding = declarations.bindings[variable.binding]
            return group.entry(key + ": " + own + "+" + digest(calledText(from: binding.start, to: binding.last, in: declarations, files: &files, members: group == .constant || group == .defaults)))
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
            /// Every type the app declares, by its simple name, and every typealias: a name such as `Array` that the
            /// app gives a type of its own isn't Swift's.
            var types = Set<String>()
        }
    }

    private static let walkTypeDecl = try! NSRegularExpression(pattern: #"^(\s*)\((struct|class|enum|actor)_decl\b[^"]*"([^"]+)".*? access=(\w+)"#)
    private static let walkAnyName = try! NSRegularExpression(pattern: #"^\s*\(\w+\b[^"]*"(\w+)""#)
    private static let walkGenericDecl = try! NSRegularExpression(pattern: #"^\s*\(\w+_decl\b[^"]*"[^"]+" "<([^"]*)>""#)
    private static let walkInherits = try! NSRegularExpression(pattern: #" inherits="([^"]*)""#)
    private static let walkExtensionDecl = try! NSRegularExpression(pattern: #"^(\s*)\(extension_decl\b[^"]*"([^"]+)""#)
    private static let walkProtocolDecl = try! NSRegularExpression(pattern: #"^(\s*)\(protocol(_decl)?\b[^"]*"([^"]+)""#)
    private static let walkClassName = try! NSRegularExpression(pattern: #"^\s*\(class_decl\b[^"]*"([^"]+)""#)

    /// The app's own class and protocol names, from the printout's declaration lines.
    static func names(inDump dump: String) -> Walk.Names {
        var names = Walk.Names()
        for raw in lines(dump) {
            guard let node = node(raw), node.opens("class_decl", "protocol", "struct_decl", "enum_decl", "actor_decl", "typealias") else { continue }
            let line = String(raw), range = NSRange(line.startIndex..., in: line)
            if !node.opens("protocol"), let m = walkAnyName.firstMatch(in: line, range: range) { names.types.insert(String(line[Range(m.range(at: 1), in: line)!])) }
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

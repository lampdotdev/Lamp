import Foundation

/// Someone's project on GitHub named in a wish typed on the desk: "https://github.com/owner/name make it a screen saver".
/// Lamp fetches the project itself (`RepoImport.clone`) and the wish is made from exactly that commit, with its credit,
/// its license files and the commit written by Lamp before the agent starts (`Store.adopt`), so the app gets the
/// project's updates later as one opened with Open a Wish from GitHub does (`AppUpdates`).
extension RepoImport {
    struct Mention: Equatable {
        let source: Source
        /// What the person asked, without the address: "make it a screen saver". Empty for an address on its own.
        let ask: String

        /// Whether the wish asks for an app made from the project: the address alone, or words that ask for one ("make",
        /// "turn it into", "build"). Anything else ("explain this repo") is the person's own question, asked first
        /// (`Store.adopt`), never rewritten into a request to make an app.
        var asksForApp: Bool {
            let words = ask.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
            guard !words.isEmpty else { return true }
            return words.contains { Self.makingWords.contains($0) }
        }

        private static let makingWords: Set<String> = [
            "make", "makes", "making", "turn", "turning", "build", "building", "adapt", "adapting", "convert", "converting",
            "port", "porting", "create", "wrap", "recreate", "remake", "rebuild",
        ]
    }

    /// The one repository on GitHub a wish names, with the rest of its words. Nil when it names none, more than one, or
    /// links to something inside one (a file, an issue, a pull request): those wishes go as they're written.
    static func mention(in text: String) -> Mention? {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var found: Source?
        var kept: [String] = []
        for token in tokens {
            let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]{}\"'“”‘’`.,;:!?"))
            guard bare.lowercased().contains("github.com") else { kept.append(token); continue }
            guard let source = source(from: bare) else { return nil }
            if let found, Credits.Source.plain(found.url) != Credits.Source.plain(source.url) || found.ref != source.ref { return nil }
            found = source
        }
        guard let found else { return nil }
        var ask = kept.joined(separator: " ").trimmed
        // "https://github.com/x/y — make it …": the dash or colon that followed the address goes with it.
        while let first = ask.first, "-–—:,".contains(first) { ask = String(ask.dropFirst()).trimmed }
        return Mention(source: found, ask: ask)
    }
}

/// A project's license and notice files, kept in the wish as they came (`Credits.Source.licenseFile` names the license),
/// each a file of its own: a project under two licenses, or with a NOTICE beside its license, keeps them apart.
enum RepoLicenses {
    /// Where they go in the wish: "Licenses/WebGL-Fluid-Simulation/LICENSE".
    static let folder = "Licenses"

    /// The top-level files of a tree that hold its terms: LICENSE, LICENCE, COPYING, UNLICENSE and NOTICE, with or
    /// without an extension or suffix ("LICENSE-MIT", "COPYING.LESSER", "NOTICE.txt"). Regular files only, none
    /// larger than a license would be, so a link or a folder of that name brings nothing in.
    static func files(in tree: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: tree, includingPropertiesForKeys: Array(keys))) ?? []
        return items.filter { item in
            guard isTerms(item.lastPathComponent),
                  let values = try? item.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 512 * 1024 else { return false }
            return true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func isTerms(_ name: String) -> Bool {
        let upper = name.uppercased()
        return ["LICENSE", "LICENCE", "COPYING", "UNLICENSE", "NOTICE"].contains { upper.hasPrefix($0) }
    }

    static func isNotice(_ name: String) -> Bool { name.uppercased().hasPrefix("NOTICE") }

    /// The SPDX id of a license text Lamp can tell for certain; nil for anything else. GPL, LGPL and AGPL texts are
    /// never named: the text is the same for "only" and "or later", which only the project's own files say.
    static func id(of text: String) -> String? {
        let plain = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        func has(_ phrase: String) -> Bool { plain.contains(phrase) }
        if has("gnu general public license") || has("gnu lesser general public license") || has("gnu affero general public license") { return nil }
        if has("permission is hereby granted, free of charge, to any person obtaining a copy")
            && has("the above copyright notice and this permission notice shall be included") { return "MIT" }
        if has("apache license") && has("version 2.0, january 2004") { return "Apache-2.0" }
        if has("mozilla public license version 2.0") { return "MPL-2.0" }
        if has("this is free and unencumbered software released into the public domain") { return "Unlicense" }
        if has("cc0 1.0 universal") { return "CC0-1.0" }
        if has("permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted") { return "ISC" }
        if has("redistribution and use in source and binary forms, with or without modification, are permitted") {
            // The advertising clause makes it the four-clause license, which is named here no more than any other.
            if has("advertising materials") { return nil }
            return has("neither the name") || has("may be used to endorse or promote products") ? "BSD-3-Clause" : "BSD-2-Clause"
        }
        return nil
    }

    /// Copies the tree's license and notice files into the wish, each under its own name, and says what the credit
    /// names: the license's id when there's one license file Lamp can tell for certain, and that file. Throws when a
    /// file can't be written: the credit isn't written without them.
    static func keep(from tree: URL, name: String, in wish: URL) throws -> (license: String?, licenseFile: String?) {
        let found = files(in: tree)
        guard !found.isEmpty else { return (nil, nil) }
        let fm = FileManager.default
        let place = "\(folder)/\(name)"
        let target = wish.appendingPathComponent(place)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for file in found {
            let copy = target.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: copy.path) { try fm.removeItem(at: copy) }
            try fm.copyItem(at: file, to: copy)
        }
        let licenses = found.filter { !isNotice($0.lastPathComponent) }
        guard let first = licenses.first else { return (nil, nil) }
        // Several licenses (MIT and Apache, say) may be a choice or both at once: only the project says which.
        let id = licenses.count == 1 ? (try? String(contentsOf: first, encoding: .utf8)).flatMap(Self.id(of:)) : nil
        return (id, "\(place)/\(first.lastPathComponent)")
    }
}

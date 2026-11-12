import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What Lamp checks before a wish leaves this Mac, as a shared file (`Sharing.export`) or a published page: that
/// others' work in it may be passed on, with its license and credit, and that nothing of the person's goes with it.
///
/// - Work under an open license (MIT, BSD, Apache and the like) goes, with its license file and its credit.
/// - Work under a share-alike license (GPL, LGPL, AGPL, MPL, CC BY-SA, ODbL) goes too, and the remix stays under it:
///   a shared file carries the code anyway, and a published page says so (`notes`).
/// - Work with no license goes too, once the person has been told (`warning`): whether to pass it on is theirs to decide.
/// - A license file the credits name has to still be in the wish.
/// - No key, token or secret Lamp keeps for the person or the app may be in what goes (`secrets`).
enum ShareCheck {
    enum Licence: Equatable { case open, shareAlike, ownTerms, none }

    /// What an SPDX id or expression lets a remix do. An `OR` takes the most open choice and an `AND` the strictest, so
    /// "MIT OR GPL-3.0" is open and "MIT AND GPL-3.0" share-alike; brackets group as SPDX has them (`WITH` binds
    /// tightest, then `AND`, then `OR`), so "GPL-3.0-only AND (MIT OR Apache-2.0)" is share-alike. A `LicenseRef-` is the
    /// work's own terms, which Lamp can't read: it goes, with its credit. An expression that doesn't parse is no license.
    static func licence(_ expression: String?) -> Licence {
        guard let expression = expression?.trimmed, !expression.isEmpty else { return .none }
        var tokens: [String] = []
        var word = ""
        for character in expression {
            if character == "(" || character == ")" || character == " " {
                if !word.isEmpty { tokens.append(word); word = "" }
                if character != " " { tokens.append(String(character)) }
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty { tokens.append(word) }
        var at = 0
        func strictness(_ licence: Licence) -> Int { [.open: 0, .ownTerms: 1, .shareAlike: 2, .none: 3][licence]! }
        func peek() -> String? { at < tokens.count ? tokens[at] : nil }
        func term() -> Licence? {
            guard let token = peek() else { return nil }
            at += 1
            var result: Licence
            if token == "(" {
                guard let inner = or(), peek() == ")" else { return nil }
                at += 1
                result = inner
            } else if ["AND", "OR", "WITH", ")"].contains(token.uppercased()) {
                return nil
            } else {
                result = single(token)
            }
            // An exception (`WITH Classpath-exception-2.0`) only loosens a licence: it's read as the license itself.
            while peek()?.uppercased() == "WITH" {
                at += 1
                guard let exception = peek(), exception != "(", exception != ")" else { return nil }
                at += 1
            }
            return result
        }
        func and() -> Licence? {
            guard var result = term() else { return nil }
            while peek()?.uppercased() == "AND" {
                at += 1
                guard let next = term() else { return nil }
                if strictness(next) > strictness(result) { result = next }
            }
            return result
        }
        func or() -> Licence? {
            guard var result = and() else { return nil }
            while peek()?.uppercased() == "OR" {
                at += 1
                guard let next = and() else { return nil }
                if strictness(next) < strictness(result) { result = next }
            }
            return result
        }
        guard let result = or(), at == tokens.count else { return .none }
        return result
    }

    /// Share-alike licenses for data rather than code (OpenStreetMap's ODbL, CDLA-Sharing): the data stays under them,
    /// not the remix as a whole. An expression is one only when each share-alike license in it is for data, in any
    /// order: "ODbL-1.0 AND GPL-3.0-only" still makes the remix GPL.
    static func isDataLicence(_ id: String?) -> Bool {
        let ids = (id ?? "").split(whereSeparator: { " ()".contains($0) }).map(String.init)
            .filter { !["AND", "OR", "WITH"].contains($0.uppercased()) }
        func isData(_ id: String) -> Bool { id.uppercased().hasPrefix("ODBL-") || id.uppercased().hasPrefix("CDLA-SHARING-") }
        let shareAlike = ids.filter { single($0) == .shareAlike }
        return !shareAlike.isEmpty && shareAlike.allSatisfy(isData)
    }

    private static func single(_ id: String) -> Licence {
        let id = id.hasSuffix("+") ? String(id.dropLast()) : id
        if id.hasPrefix("LicenseRef-") || id.hasPrefix("DocumentRef-") { return .ownTerms }
        let upper = id.uppercased()
        let shareAlike = ["GPL-", "LGPL-", "AGPL-", "MPL-", "EPL-", "EUPL-", "CC-BY-SA-", "CC-BY-NC-SA-", "ODBL-", "OSL-", "CDDL-", "CECILL-"]
        if shareAlike.contains(where: upper.hasPrefix) { return .shareAlike }
        // Licenses that don't allow passing a remix on as anyone likes (no derivatives, no commercial use) are taken
        // as the work's own terms: credited, and named on a published page.
        if upper.hasPrefix("CC-BY-NC") || upper.hasPrefix("CC-BY-ND") { return .ownTerms }
        let open = ["MIT", "MIT-0", "0BSD", "ISC", "ZLIB", "UNLICENSE", "CC0-1.0", "WTFPL", "BSL-1.0", "PDDL-1.0", "ODC-BY-1.0",
                    "OFL-1.1", "APACHE-2.0", "APACHE-1.1", "PYTHON-2.0", "PSF-2.0", "X11", "NCSA", "UPL-1.0", "CC-BY-4.0",
                    "CC-BY-3.0", "CC-BY-2.0", "MS-PL", "ARTISTIC-2.0", "BLUEOAK-1.0.0", "POSTGRESQL"]
        if open.contains(upper) || upper.hasPrefix("BSD-") { return .open }
        // An id Lamp doesn't know is still a license its author chose: credited, with its own terms.
        return .ownTerms
    }

    /// Why the wish can't leave this Mac, or nil when it can: a license or notice file the credits name is gone, and a
    /// copy without it couldn't be shared on. Work with no license isn't a reason (`warning`).
    static func refusal(of project: LampProject, credits: Credits) -> Sharing.ImportError? {
        for source in credits.upstream {
            guard let gone = source.termsFiles.first(where: { !FileManager.default.fileExists(atPath: project.dir.appendingPathComponent($0).path) })
            else { continue }
            return Sharing.ImportError("\(project.name) can't be shared.",
                                       detail: "The license of \(source.name) is missing from it. Ask Lamp to put \(gone) back.")
        }
        return nil
    }

    /// The work in the wish that came with no license, which the person is told of before it leaves this Mac.
    static func unlicensed(_ credits: Credits) -> [Credits.Source] {
        credits.upstream.filter { licence($0.license) == .none }
    }

    /// What the person is told before a wish with work under no license leaves this Mac, or nil when it has none. Its
    /// author may not want it passed on, which only the person can weigh; Lamp says so and lets them decide.
    static func warning(of project: LampProject, credits: Credits) -> Sharing.ImportError? {
        warningLine(credits).map { Sharing.ImportError("\(project.name) uses work that came with no license.", detail: $0) }
    }

    /// The same in one line, which a sheet shows among its facts when what it puts up can be seen by others.
    static func warningLine(_ credits: Credits) -> String? {
        let unlicensed = unlicensed(credits)
        guard !unlicensed.isEmpty else { return nil }
        let lines = unlicensed.map(Credits.line(for:))
        let names = lines.count < 3 ? lines.joined(separator: " and ") : lines.dropLast().joined(separator: ", ") + ", and " + lines.last!
        return "\(names) came with no license. Make sure you're comfortable sharing \(unlicensed.count == 1 ? "it" : "them")."
    }

    /// What the person last agreed to share with no license, for each wish: they're asked once, and again only when the
    /// wish takes in more such work. Kept in Lamp's settings, not the wish's folder, where the agent could write it.
    /// Kept by the wish's own identity rather than its folder's name, which a later wish may take.
    static func accepted(_ project: LampProject, credits: Credits) -> Bool {
        let wanted = fingerprint(credits)
        return wanted.isEmpty || (UserDefaults.standard.dictionary(forKey: acceptedKey)?[key(project)] as? [String]).map { Set(wanted).isSubset(of: $0) } == true
    }

    /// Kept as agreed to: `sources` is what the person was shown (`fingerprint`), never what the wish holds by the time
    /// they answer, which a change landing meanwhile may have added to.
    static func accept(_ project: LampProject, sources: [String]) {
        var all = UserDefaults.standard.dictionary(forKey: acceptedKey) ?? [:]
        all[key(project)] = sources
        UserDefaults.standard.set(all, forKey: acceptedKey)
    }

    private static let acceptedKey = "sharedWithNoLicense"

    private static func key(_ project: LampProject) -> String { project.instance.isEmpty ? project.id : project.instance }

    /// The unlicensed work named in a warning, so an answer to it is held to what it named.
    static func fingerprint(_ credits: Credits) -> [String] {
        unlicensed(credits).map { [$0.name, $0.url ?? "", $0.commit ?? ""].joined(separator: "\u{1F}") }.sorted()
    }

    /// What a published page says of the licenses of what it's based on: one line for each share-alike licence, and one
    /// for work under its own terms.
    static func notes(for credits: Credits) -> [String] {
        credits.upstream.compactMap(note(for:))
    }

    private static func note(for source: Credits.Source) -> String? {
        switch licence(source.license) {
        case .shareAlike where isDataLicence(source.license):
            "\(source.name) is \(source.license ?? ""): it stays under that license, credited, in this remix."
        case .shareAlike: "\(source.name) is \(source.license ?? ""), so this remix is too: anyone may share it on under the same license."
        case .ownTerms: "\(source.name) is used under its own terms (\(source.license ?? ""))."
        case .open, .none: nil
        }
    }

    /// The same lines for a card the person reads before sending, in two parts: `shown`, what changes what they may do
    /// (a remix that becomes share-alike, work that forbids commercial use or changes), and `terms`, one line for each
    /// source that's only credited under its own terms, which the card folds. A wish built on many data sets has a
    /// line for each, and unfolded they push the card's buttons out of sight.
    static func cardNotes(for credits: Credits) -> (shown: [String], terms: [String]) {
        var shown: [String] = [], terms: [String] = []
        for source in credits.upstream {
            guard let line = note(for: source) else { continue }
            if isCreditOnly(source.license) { terms.append(line) } else { shown.append(line) }
        }
        return (shown, terms)
    }

    /// Whether a license asks nothing of a remix beyond its credit: its own terms, or share-alike data that stays under
    /// its license. Not one that forbids commercial use or changes, anywhere in an expression.
    static func isCreditOnly(_ expression: String?) -> Bool {
        let restrictive = (expression ?? "").uppercased().split(whereSeparator: { " ()".contains($0) })
            .contains { $0.hasPrefix("CC-BY-NC") || $0.hasPrefix("CC-BY-ND") }
        switch licence(expression) {
        case .ownTerms: return !restrictive
        case .shareAlike: return isDataLicence(expression) && !restrictive
        case .open, .none: return false
        }
    }

    // MARK: Secrets

    /// The values Lamp keeps that must never leave in a wish: the person's provider keys, the app's own secrets and
    /// its token for Lamp's gateway. Only ones long enough not to turn up by chance.
    static func keptSecrets(of project: LampProject) -> [String] {
        var values = Provider.keyProviders.compactMap { KeyStore.key(for: $0.id) }
        values += AppSecrets.values(app: project.instance).compactMap { String(data: $0, encoding: .utf8) }
        if let token = try? String(contentsOf: project.dir.appendingPathComponent(".lamp/token"), encoding: .utf8) { values.append(token) }
        return values.map(\.trimmed).filter { $0.count >= 16 }
    }

    /// Shapes of keys and tokens whoever's they are: a private key, and the prefixes services give their keys.
    /// Written in Resources/share-rules.json (`ShareRules`), which lamp's command line reads too.
    static let tokenShapes: [NSRegularExpression] = ShareRules.shared.tokenShapes.map { try! NSRegularExpression(pattern: $0.pattern) }

    /// The files in `folder` (as staged to go) that hold one of `known` or something shaped like a key, by their path in it.
    /// Every file is read, whatever its size, in pieces that overlap by more than any key is long, so a key across two
    /// pieces is still found; one that can't be read is counted as holding one, since it can't be said not to.
    static func secrets(in folder: URL, known: [String]) -> [String] {
        let fm = FileManager.default
        var found: [String] = []
        let piece = 4 << 20, overlap = 4096
        for case let file as URL in fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) ?? FileManager.DirectoryEnumerator() {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            guard let handle = try? FileHandle(forReadingFrom: file) else { found.append(Sharing.relativePath(of: file, in: folder)); continue }
            defer { try? handle.close() }
            var tail = Data()
            while true {
                let next: Data
                do { next = try handle.read(upToCount: piece) ?? Data() } catch {
                    found.append(Sharing.relativePath(of: file, in: folder))
                    break
                }
                if next.isEmpty { break }
                // Text in any file, pictures included: a key pasted into a JSON or left in a picture's metadata goes as well.
                let text = String(decoding: tail + next, as: UTF8.self)
                if known.contains(where: { text.contains($0) })
                    || tokenShapes.contains(where: { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }) {
                    found.append(Sharing.relativePath(of: file, in: folder))
                    break
                }
                tail = next.suffix(overlap)
            }
        }
        return found.sorted()
    }
}

/// The mark a picture made with AI carries in itself: IPTC's digital source type "trainedAlgorithmicMedia" in its XMP,
/// the field image tools and sites read to label AI pictures.
enum AIMark {
    static let namespace = "http://iptc.org/std/Iptc4xmpExt/2008-02-29/"
    static let generated = "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"

    /// The PNG with the mark, or as it was when it can't be read.
    static func marked(_ png: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return png }
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace as CFString, "Iptc4xmpExt" as CFString, nil)
        CGImageMetadataSetValueWithPath(metadata, nil, "Iptc4xmpExt:DigitalSourceType" as CFString, generated as CFString)
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return png }
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : png
    }

    static func isMarked(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else { return false }
        let value = CGImageMetadataCopyStringValueWithPath(metadata, nil, "Iptc4xmpExt:DigitalSourceType" as CFString)
        return value as String? == generated
    }
}

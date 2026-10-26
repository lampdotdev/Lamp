import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What Lamp checks before a wish leaves this Mac, as a shared file (`Sharing.export`) or a published page: that
/// others' work in it may be passed on, with its licence and credit, and that nothing of the person's goes with it.
///
/// - Work under an open licence (MIT, BSD, Apache and the like) goes, with its licence file and its credit.
/// - Work under a share-alike licence (GPL, LGPL, AGPL, MPL, CC BY-SA, ODbL) goes too, and the remix stays under it:
///   a shared file carries the code anyway, and a published page says so (`notes`).
/// - Work with no licence can be used on this Mac but not passed on: the share is refused, naming it.
/// - A licence file the credits name has to still be in the wish.
/// - No key, token or secret Lamp keeps for the person or the app may be in what goes (`secrets`).
enum ShareCheck {
    enum Licence: Equatable { case open, shareAlike, ownTerms, none }

    /// What an SPDX id or expression lets a remix do. An `OR` takes the most open choice and an `AND` the strictest, so
    /// "MIT OR GPL-3.0" is open and "MIT AND GPL-3.0" share-alike. A `LicenseRef-` is the work's own terms, which Lamp
    /// can't read: it goes, with its credit.
    static func licence(_ expression: String?) -> Licence {
        guard let expression = expression?.trimmed, !expression.isEmpty else { return .none }
        let alternatives = expression.replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " ")
            .components(separatedBy: " OR ")
        func strictness(_ licence: Licence) -> Int { [.open: 0, .ownTerms: 1, .shareAlike: 2, .none: 3][licence]! }
        let each = alternatives.map { alternative in
            alternative.components(separatedBy: " AND ").map { term in
                single(term.components(separatedBy: " WITH ")[0].trimmed)
            }.max { strictness($0) < strictness($1) } ?? .none
        }
        return each.min { strictness($0) < strictness($1) } ?? .none
    }

    private static func single(_ id: String) -> Licence {
        let id = id.hasSuffix("+") ? String(id.dropLast()) : id
        if id.hasPrefix("LicenseRef-") || id.hasPrefix("DocumentRef-") { return .ownTerms }
        let upper = id.uppercased()
        let shareAlike = ["GPL-", "LGPL-", "AGPL-", "MPL-", "EPL-", "EUPL-", "CC-BY-SA-", "CC-BY-NC-SA-", "ODBL-", "OSL-", "CDDL-", "CECILL-"]
        if shareAlike.contains(where: upper.hasPrefix) { return .shareAlike }
        // Licences that don't allow passing a remix on as anyone likes (no derivatives, no commercial use) are taken
        // as the work's own terms: credited, and named on a published page.
        if upper.hasPrefix("CC-BY-NC") || upper.hasPrefix("CC-BY-ND") { return .ownTerms }
        let open = ["MIT", "MIT-0", "0BSD", "ISC", "ZLIB", "UNLICENSE", "CC0-1.0", "WTFPL", "BSL-1.0", "PDDL-1.0", "ODC-BY-1.0",
                    "OFL-1.1", "APACHE-2.0", "APACHE-1.1", "PYTHON-2.0", "PSF-2.0", "X11", "NCSA", "UPL-1.0", "CC-BY-4.0",
                    "CC-BY-3.0", "CC-BY-2.0", "MS-PL", "ARTISTIC-2.0", "BLUEOAK-1.0.0", "POSTGRESQL"]
        if open.contains(upper) || upper.hasPrefix("BSD-") { return .open }
        // An id Lamp doesn't know is still a licence its author chose: credited, with its own terms.
        return .ownTerms
    }

    /// Why the wish can't leave this Mac, or nil when it can.
    static func refusal(of project: LampProject, credits: Credits) -> Sharing.ImportError? {
        let unlicensed = credits.upstream.filter { licence($0.license) == .none }
        if !unlicensed.isEmpty {
            let names = unlicensed.map(Credits.line(for:)).joined(separator: ", ")
            return Sharing.ImportError("\(project.name) can't be shared.",
                                       detail: "It uses \(names), which came with no licence. It can still be used on this Mac.")
        }
        let missing = credits.upstream.filter { source in
            source.licenseFile.map { !FileManager.default.fileExists(atPath: project.dir.appendingPathComponent($0).path) } ?? false
        }
        if let first = missing.first {
            return Sharing.ImportError("\(project.name) can't be shared.",
                                       detail: "The licence of \(first.name) is missing from it. Ask Lamp to put \(first.licenseFile ?? "it") back.")
        }
        return nil
    }

    /// What a published page says of the licences of what it's based on: one line for each share-alike licence, and one
    /// for work under its own terms.
    static func notes(for credits: Credits) -> [String] {
        var notes: [String] = []
        for source in credits.upstream {
            switch licence(source.license) {
            case .shareAlike: notes.append("\(source.name) is \(source.license ?? ""), so this remix is too: anyone may share it on under the same licence.")
            case .ownTerms: notes.append("\(source.name) is used under its own terms (\(source.license ?? "")).")
            case .open, .none: break
            }
        }
        return notes
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
    static let tokenShapes: [NSRegularExpression] = [
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"\bsk-(or-v1-|ant-|proj-)?[A-Za-z0-9_\-]{32,}"#,      // OpenRouter, Anthropic, OpenAI
        #"\bgh[pousr]_[A-Za-z0-9]{36,}"#,                        // GitHub
        #"\bgithub_pat_[A-Za-z0-9_]{60,}"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,                                // AWS
        #"\bAIza[0-9A-Za-z_\-]{35}\b"#,                          // Google
        #"\bxox[abprs]-[A-Za-z0-9\-]{20,}"#,                     // Slack
        #"\b(sk|rk)_live_[A-Za-z0-9]{20,}"#,                     // Stripe
    ].map { try! NSRegularExpression(pattern: $0) }

    /// The files in `folder` (as staged to go) that hold one of `known` or something shaped like a key, by their path in it.
    static func secrets(in folder: URL, known: [String]) -> [String] {
        let fm = FileManager.default
        var found: [String] = []
        for case let file as URL in fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) ?? FileManager.DirectoryEnumerator() {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true,
                  (values.fileSize ?? 0) <= 20_000_000, let data = try? Data(contentsOf: file) else { continue }
            // Text in any file, pictures included: a key pasted into a JSON or left in a picture's metadata goes as well.
            let text = String(decoding: data, as: UTF8.self)
            let hit = known.contains { text.contains($0) }
                || tokenShapes.contains { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
            if hit { found.append(Sharing.relativePath(of: file, in: folder)) }
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

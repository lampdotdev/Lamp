import XCTest
@testable import Lamp

/// What a TV takes from Lamp: Samsung's ids in their fixed shape, a manifest it can parse, and signature files whose
/// signature holds over SignedInfo as a verifier canonicalizes it (the same way that reproduced Tizen Studio's own).
final class TVKitTests: XCTestCase {
    private let project = LampProject(id: "tv-clock", name: "TV Clock & Co", exe: "TVClock", dir: URL(fileURLWithPath: "/tmp/tv-clock"))

    func testSamsungIdsAndManifest() throws {
        let ids = TVTemplate.tizenIDs(for: project)
        XCTAssertEqual(ids.package.count, 10)
        XCTAssertTrue(ids.package.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
        XCTAssertEqual(ids.app, ids.package + ".TVClock")
        XCTAssertEqual(TVTemplate.tizenIDs(for: project).package, ids.package, "the same app keeps the same package id")
        let manifest = try XMLDocument(xmlString: TVTemplate.tizenConfig(for: project, guarded: nil))
        XCTAssertEqual(try manifest.nodes(forXPath: "//*[local-name()='name']").first?.stringValue, "TV Clock & Co")
        XCTAssertTrue(TVTemplate.webOSID(for: project).hasSuffix("tv-clock"))
    }

    func testSignatureHoldsOverCanonicalSignedInfo() throws {
        let key = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil))
        let file = try TizenSigning.signatureFile(id: "AuthorSignature", role: "author",
                                                  files: [("index.html", Data("<p>hi</p>".utf8)), ("js/app.js", Data("1".utf8))],
                                                  key: key, chain: [])
        let xml = String(decoding: file, as: UTF8.self)
        let start = try XCTUnwrap(xml.range(of: "<SignedInfo>")), end = try XCTUnwrap(xml.range(of: "</SignedInfo>"))
        let canonical = String(xml[start.lowerBound..<end.upperBound])
            .replacingOccurrences(of: "<SignedInfo>", with: "<SignedInfo xmlns=\"http://www.w3.org/2000/09/xmldsig#\">")
        let value = try XCTUnwrap(xml.components(separatedBy: "<SignatureValue>").last?.components(separatedBy: "</SignatureValue>").first)
        let signature = try XCTUnwrap(Data(base64Encoded: value))
        XCTAssertTrue(SecKeyVerifySignature(try XCTUnwrap(SecKeyCopyPublicKey(key)), .rsaSignatureMessagePKCS1v15SHA512,
                                            Data(canonical.utf8) as CFData, signature as CFData, nil))
        XCTAssertTrue(xml.contains("<Reference URI=\"js/app.js\">"))
        XCTAssertNoThrow(try XMLDocument(data: file))
    }
}

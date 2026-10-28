// Signs a release DMG for Sparkle and writes the sparkle.json the update feed reads (updates/api/appcast.js).
// Usage: SPARKLE_PRIVATE_KEY=<base64 Ed25519 key> swift scripts/sparkle-sign.swift Lamp-0.4.2.dmg 0.4.2 > sparkle.json
// A nightly gives its build number and, after it, the version people see:
//   … sparkle-sign.swift Lamp-0.4.2+37.dmg 0.4.2.37 0.4.2+37 > sparkle.json
// The key's public half is SUPublicEDKey in build.sh; Sparkle refuses updates that don't verify against it.
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4,
      let encoded = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      let raw = Data(base64Encoded: encoded),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
    FileHandle.standardError.write(Data("usage: SPARKLE_PRIVATE_KEY=… sparkle-sign.swift <dmg> <version> [<short version>]\n".utf8))
    exit(1)
}
let file = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
let signature = try key.signature(for: file)
guard key.publicKey.isValidSignature(signature, for: file) else { exit(2) }
let info: [String: Any] = [
    "version": arguments[2], "shortVersion": arguments.count > 3 ? arguments[3] : arguments[2], "minimumSystemVersion": "14.0",
    "length": file.count, "signature": signature.base64EncodedString(),
]
let json = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(json)

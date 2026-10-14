import Foundation
import CryptoKit

// Chrome launches one instance per service-worker connection. The session never comes from a web page.
let session = UUID().uuidString
let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let config = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("config.json"))) as! [String: Any]
let secret = try Data(contentsOf: URL(fileURLWithPath: config["secretPath"] as! String))
let key = SymmetricKey(data: secret)
let port = config["port"] as! Int
let input = FileHandle.standardInput
let output = FileHandle.standardOutput
func exact(_ n: Int) -> Data? {
    var data = Data()
    while data.count < n {
        guard let chunk = try? input.read(upToCount: n - data.count), !chunk.isEmpty else { return nil }
        data.append(chunk)
    }
    return data
}
func reply(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value)
    var size = UInt32(data.count).littleEndian
    output.write(Data(bytes: &size, count: 4))
    output.write(data)
}
while let length = exact(4) {
    let size = length.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    guard size < 300_000, let raw = exact(Int(size)), var body = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { break }
    let nonce = UUID().uuidString
    body["nonce"] = nonce
    body["session"] = session
    let bytes = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/browser/native")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 5
    request.httpBody = bytes
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(Data(HMAC<SHA256>.authenticationCode(for: bytes, using: key)).base64EncodedString(), forHTTPHeaderField: "X-Lamp-Signature")
    let wait = DispatchSemaphore(value: 0)
    var answer: [String: Any] = ["error": "Open Lamp on this Mac, then try again."]
    URLSession.shared.dataTask(with: request) { data, _, _ in
        defer { wait.signal() }
        guard let data, let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let payload = envelope["payload"], let signature = envelope["signature"], let sig = Data(base64Encoded: signature),
              HMAC<SHA256>.isValidAuthenticationCode(sig, authenticating: Data((nonce + "." + payload).utf8), using: key),
              let value = Data(base64Encoded: payload), let decoded = (try? JSONSerialization.jsonObject(with: value)) as? [String: Any] else { return }
        answer = decoded
    }.resume()
    wait.wait()
    reply(answer)
}

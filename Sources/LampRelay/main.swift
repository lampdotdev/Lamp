import CryptoKit
import Foundation
import LampRelayKit

// The relay between a TV app and its phones (`Relay`), as a process of its own beside Lamp, which starts it while a TV
// app takes players and tells it, a line of JSON at a time on its input, what to do:
//
//   {"op":"start","key":"<base64>","port":47900}       the controllers' key, and the port it had before
//   {"op":"session","app":"…","generation":0,"pagePort":47860,"page":"http://…/","hosts":["…"]}
//   {"op":"end","app":"…"}
//   {"op":"room","app":"wish:…","key":"<base64>","apps":[{"peer":"tv","kind":"tv","name":"the TV app"},…],"keep":"/…"}   a wish's room,
//                                                with its key and the folder Lamp keeps its shared collections in
//   {"op":"end-room","app":"wish:…","forget":true}   with forget, the wish is gone and what was kept for it goes too
//   {"op":"say","app":"wish:…","to":["screen.k3j9x0ab",…],"data":{…},"ask":1}   Lamp's own word to those copies
//
// It says where it's listening on its output ({"op":"ready","port":…}), who is in each room as that changes
// ({"op":"room","app":…,"peers":[…]}), which copies each of Lamp's words went to ({"op":"said","ask":1,"to":[…]}), what a copy said to Lamp
// ({"op":"heard","app":…,"from":"screen.k3j9x0ab","data":…}), and ends when its input does, so it never outlives the Lamp that started it.

setvbuf(stdout, nil, _IOLBF, 0)
var relay: Relay?

func say(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
    print(String(decoding: data, as: UTF8.self))
}

while let line = readLine() {
    guard let command = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
    switch command["op"] as? String {
    case "start":
        guard relay == nil, let key = (command["key"] as? String).flatMap({ Data(base64Encoded: $0) }), key.count == 32 else { continue }
        let started = Relay(key: SymmetricKey(data: key))
        relay = started
        // Not listening, the relay is no use: it ends, and Lamp starts another.
        started.onStopped = { exit(1) }
        started.onRoomChanged = { room, members in say(["op": "room", "app": room, "peers": members]) }
        started.onHeard = { room, copy, data in say(["op": "heard", "app": room, "from": copy, "data": data]) }
        started.start(port: UInt16(clamping: command["port"] as? Int ?? 0)) { port in
            say(["op": "ready", "port": port.map { Int($0) as Any } ?? NSNull()])
            if port == nil { exit(1) }
        }
    case "session":
        guard let relay, let app = command["app"] as? String, let generation = command["generation"] as? Int else { continue }
        relay.configure(app: app, Relay.Session(generation: generation, pagePort: (command["pagePort"] as? Int).map { UInt16(clamping: $0) },
                                                page: command["page"] as? String, hosts: command["hosts"] as? [String] ?? []))
    case "end":
        guard let relay, let app = command["app"] as? String else { continue }
        relay.end(app: app)
    case "room":
        guard let relay, let app = command["app"] as? String,
              let key = (command["key"] as? String).flatMap({ Data(base64Encoded: $0) }), key.count == WishChannel.keySize else { continue }
        var apps: [String: (kind: String, name: String)] = [:], waiting: Set<String> = []
        for each in command["apps"] as? [[String: Any]] ?? [] {
            guard let peer = each["peer"] as? String else { continue }
            apps[peer] = (each["kind"] as? String ?? "", each["name"] as? String ?? "")
            if each["waiting"] as? Bool == true { waiting.insert(peer) }
        }
        relay.configureRoom(app, key: key, apps: apps, waiting: waiting, keep: (command["keep"] as? String).map { URL(fileURLWithPath: $0, isDirectory: true) })
    case "say":
        guard let relay, let app = command["app"] as? String, let to = command["to"] as? [String], let data = command["data"] else { continue }
        let ask = command["ask"] as? Int ?? 0
        relay.say(in: app, to: to, data: data) { reached in say(["op": "said", "ask": ask, "to": reached]) }
    case "end-room":
        guard let relay, let app = command["app"] as? String else { continue }
        relay.endRoom(app, forget: command["forget"] as? Bool == true)
    default:
        continue
    }
}
exit(0)

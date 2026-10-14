import Foundation
import CryptoKit

/// The wand inside an iPhone app on the person's own phone (`LampWand` in LampSupport.swift): a sheet in the app
/// with its recent chat and a message box. On the Mac the app never speaks to the agent (Lamp draws the chat
/// beside it); a phone has no room beside the app and Lamp can't draw on it, so here the app carries the chat
/// and sends what's typed to Lamp. Everything that keeps that narrow is here: only for an app set to open on a phone, only from the network, one change at a
/// time and a few dozen a day, never from this Mac itself (where the agent and the app's other copies run),
/// every message sealed with the app's phone secret, and each one sent once whatever is retried. What
/// arrives becomes an ordinary message in the app's chat, marked as from the iPhone, so the agent, its
/// approvals, the sandbox and versions are the same as for one typed on the Mac.
enum PhoneWand {
    /// What the app's sheet follows: a change from typing it to the app coming back with it.
    enum Phase: String {
        case working, waiting, installing, done, failed
    }

    /// One message sent from the phone, from its arrival to how its turn ended.
    struct Request {
        let id: String
        var project: String
        let arrived: Date
        /// Set when its turn ends; until then the phase is read off the turn as it goes (`Store.wandPhase`).
        var ended: Phase?
        /// The turn ended with the agent's questions: the sheet's box answers them.
        var asked = false
        /// The turn changed the app, rather than only replying.
        var changed = false
        /// Why it didn't work, in a few plain words.
        var note: String?
        /// Turned away when it came, and why: kept so the phone's retry of a message whose answer was lost hears
        /// the same thing, and puts what was typed back in its box.
        var turnedAway: TurnedAway?
    }

    enum TurnedAway: Equatable {
        /// Refused, with why in the person's words.
        case refused(String)
        /// Another change from the phone was going: the one with this id.
        case busy(String)
    }

    /// A message the route turned away, kept as its answer.
    static func turnedAway(_ id: String, for project: String, _ why: TurnedAway, at now: Date = Date()) -> Request {
        var request = Request(id: id, project: project, arrived: now)
        request.ended = .failed
        request.turnedAway = why
        if case .refused(let reason) = why { request.note = reason }
        return request
    }

    /// What a message turned away is answered with, every time it's sent: nil for one that was taken.
    static func answer(toTurnedAway request: Request?) -> [String: Any]? {
        switch request?.turnedAway {
        case .refused(let why): ["refused": why]
        case .busy(let going): ["busy": true, "going": going]
        case nil: nil
        }
    }

    /// The most messages one app's wand may send in a day. A person changing an app from the phone sends a
    /// handful; the app's own code, which can send them too, mustn't be able to keep the agent working for ever.
    static let dailyLimit = 30

    /// Why a message from the phone is turned away, if it is: counted before it's taken, so the message after
    /// the day's last one is refused, not sent on.
    static func refusal(of text: String, ready: Bool, sentToday: Int) -> String? {
        if text.isEmpty { return "There's nothing to send." }
        if text.count > 4000 { return "That's too long. Say it in fewer words." }
        if !ready { return "Lamp on your Mac isn't ready yet." }
        if sentToday >= dailyLimit { return "That's all the changes from your iPhone for today. Lamp on your Mac still takes them." }
        return nil
    }

    /// Whether this app's wand works now: the app opens on the person's phone, where the change will be
    /// installed. Otherwise the app hides its wand.
    @MainActor static func isAvailable(for project: LampProject) -> Bool {
        project.platform.hasIOS && project.onIOS && project.device != nil
    }

    // MARK: - The sealed envelope

    /// How long a message may take to arrive, either way, before it's turned away: past that, a copy of it
    /// taken off the air is no use to anyone. The phone's clock and the Mac's are both set by the network.
    static let freshness: TimeInterval = 300

    /// The key both sides seal with, made from the secret that reached the phone inside its build and never
    /// over the network. It's not the key `/ai/keys` is sealed with, so nothing sealed for one passes as the other.
    static func key(secret: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data("lamp-wand\n\(secret)".utf8)))
    }

    enum Refusal: Error, Equatable { case unreadable, stale }

    /// The message in a request's body, when it was sealed with this app's secret and is fresh.
    static func open(_ body: Data, secret: String, now: Date = Date()) throws -> [String: Any] {
        guard let outer = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let sealed = (outer["sealed"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let opened = try? AES.GCM.open(box, using: key(secret: secret)),
              let message = (try? JSONSerialization.jsonObject(with: opened)) as? [String: Any],
              message["op"] is String, message["reply"] == nil,
              let at = message["at"] as? Double else { throw Refusal.unreadable }
        guard abs(now.timeIntervalSince1970 - at) <= freshness else { throw Refusal.stale }
        return message
    }

    /// A reply sealed the same way, so what the app is told (its chat among it) isn't on the air either. It says
    /// it's a reply, so neither side takes a message going the other way for one meant for it.
    static func seal(_ message: [String: Any], secret: String) -> [String: Any] {
        var message = message
        message["reply"] = true
        guard let json = try? JSONSerialization.data(withJSONObject: message),
              let sealed = try? AES.GCM.seal(json, using: key(secret: secret)).combined else { return ["error": "Couldn't seal the reply."] }
        return ["sealed": sealed.base64EncodedString()]
    }

    // MARK: - Sent once

    /// The ids of messages already taken, with when, kept across a relaunch: the phone sends a message again
    /// until it hears back, and a copy taken off the air is the same message too, so each id is taken once.
    /// Kept a day, far longer than `freshness`, past which a copy is refused anyway.
    struct Taken {
        /// Each id with when it came, the app it came for, and whether it counts toward the day's limit (it was
        /// sent on, not turned away).
        private(set) var ids: [String: (at: Date, app: String, counted: Bool)] = [:]
        let file: URL?

        init(file: URL?) {
            self.file = file
            if let file, let data = try? Data(contentsOf: file),
               let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] {
                ids = saved.compactMapValues { entry in
                    guard let at = entry["at"] as? Double, let app = entry["app"] as? String else { return nil }
                    return (Date(timeIntervalSince1970: at), app, entry["counted"] as? Bool ?? true)
                }
            }
        }

        func contains(_ id: String) -> Bool { ids[id] != nil }
        func contains(_ id: String, for app: String) -> Bool { ids[id]?.app == app }

        /// How many messages the app's wand sent on in the last day.
        func count(for app: String, now: Date = Date()) -> Int {
            ids.values.filter { $0.app == app && $0.counted && now.timeIntervalSince($0.at) < 86_400 }.count
        }

        /// Takes the id; false when it was taken before.
        mutating func take(_ id: String, for app: String = "", counted: Bool = true, now: Date = Date()) -> Bool {
            ids = ids.filter { now.timeIntervalSince($0.value.at) < 86_400 }
            guard ids[id] == nil else { return false }
            ids[id] = (now, app, counted)
            let saved = ids.mapValues { ["at": $0.at.timeIntervalSince1970, "app": $0.app, "counted": $0.counted] as [String: Any] }
            if let file, let data = try? JSONSerialization.data(withJSONObject: saved) {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
            return true
        }
    }

    /// What the sheet shows of the chat: the requests and the agent's words, newest last, without Lamp's own
    /// status lines, tools or errors (those are for the Mac's chat).
    static func lines(from log: [LogLine], limit: Int = 24) -> [[String: Any]] {
        log.filter { line in
            switch line.kind {
            case .user, .agent, .ask, .result: !line.text.trimmed.isEmpty
            default: false
            }
        }
        .suffix(limit)
        .map { line in
            let text = plain(line.text)
            return ["me": line.kind == .user, "text": text.count > 800 ? String(text.prefix(799)) + "…" : text]
        }
    }

    /// The first sentence of what the agent said it's about to do, for the line under "Working…".
    static func doing(from log: [LogLine]) -> String? {
        guard let start = log.lastIndex(where: { $0.kind == .user }),
              let said = log[(start + 1)...].first(where: { $0.kind == .agent && !$0.text.trimmed.isEmpty }) else { return nil }
        let text = plain(said.text)
        let sentence = text.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init)?.trimmed ?? text
        return sentence.count > 90 ? String(sentence.prefix(89)) + "…" : sentence
    }

    /// Markdown as plain words: the phone shows text, not formatting.
    static func plain(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: #"(?m)^#+\s*"#, with: "", options: .regularExpression)
            .trimmed
    }
}

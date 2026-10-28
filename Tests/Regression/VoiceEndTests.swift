import XCTest
@testable import Lamp

/// When a recording ends, as the hosts decide it: `LampVoiceEnd` in LampPage.swift (Mac, iPhone, iPad) and in Android's
/// LampPageGateway.kt, each compiled from its own source and run through the same recordings, by level and time. Speech
/// from the very first moment is heard as speech; sound that never stood out from the room is still sent once it has
/// really stopped, and never ended as finished while it goes on; quiet is only quiet that was heard, so a recording
/// whose audio stops coming mid-sentence ends as lost, not as finished; and the clock ends it either way. On Android also `LampVoiceTake`, the
/// loop around the microphone: a recording cancelled while no audio comes ends at once, on its own, and a read that
/// fails is a failure, not a wait.
final class VoiceEndTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Each recording: 40 ms levels, then (when they run out) the clock going on with no audio at all.
    private let recordings: [(name: String, levels: [Double], expect: String, by: ClosedRange<Double>)] = {
        func run(_ seconds: Double, _ level: Double) -> [Double] { Array(repeating: level, count: Int((seconds / 0.04).rounded())) }
        let words = run(0.6, 0.2) + run(0.2, 0.003) + run(0.6, 0.2)
        return [
            // Talking from the moment it opens, with the pause between words.
            ("straight away", words + run(6, 0.003), "quiet", 2.4...2.8),
            // Sound from the first moment that never dips: not dropped, and not ended while it goes on, only once
            // it has really stopped.
            ("steady", run(7, 0.1) + run(3, 0.001), "quiet", 8.1...8.4),
            // ... and when it never stops, the limit: not something to act on.
            ("steady to the limit", run(16, 0.1), "cap", 14.9...15.1),
            // Speech that's been heard and then goes on without a pause isn't taken for the room.
            ("talking on", words + run(4, 0.2) + run(3, 0.003), "quiet", 6.4...6.8),
            ("silence", run(7, 0.001), "nothing", 5.9...6.1),
            // Audio stops coming mid-sentence (the microphone stalls or goes away): quiet is only what was heard, so
            // this ends as lost, which nothing acts on, a second after the last sound came.
            ("audio stops", words, "lost", 2.35...2.5),
            ("sound then nothing", run(3, 0.1), "lost", 3.95...4.1),
            ("no audio", [], "nothing", 5.9...6.1),
            ("too long", (0..<40).flatMap { _ in run(0.2, 0.2) + run(0.2, 0.003) }, "cap", 14.9...15.1),
        ]
    }()

    private func driverLines(_ arrays: (String) -> String) -> String {
        recordings.map { arrays("\"\($0.name)\", " + ($0.levels.isEmpty ? "EMPTY" : "[" + $0.levels.map { String($0) }.joined(separator: ", ") + "]")) }.joined(separator: "\n")
    }

    private func check(_ output: String, _ host: String) {
        let got = Dictionary(uniqueKeysWithValues: output.split(separator: "\n").compactMap { line -> (String, (String, Double))? in
            let p = line.split(separator: "|").map(String.init)
            return p.count == 3 ? (p[0], (p[1], Double(p[2]) ?? -1)) : nil
        })
        for r in recordings {
            guard let (ended, at) = got[r.name] else { XCTFail("\(host): \(r.name) gave nothing"); continue }
            XCTAssertEqual(ended, r.expect, "\(host): \(r.name)")
            XCTAssertTrue(r.by.contains(at), "\(host): \(r.name) ended at \(at)")
        }
    }

    private func block(_ source: String, from start: String) throws -> String {
        let a = try XCTUnwrap(source.range(of: start))
        let b = try XCTUnwrap(source.range(of: "\n}\n", range: a.upperBound..<source.endIndex))
        return String(source[a.lowerBound..<b.upperBound])
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = out; p.standardError = out
        try p.run()
        // A recording that never ends would hang here: it's stopped, and fails, after a minute.
        let limit = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: limit)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        limit.cancel()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(p.terminationStatus, 0, text)
        return text
    }

    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-end-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testTheAppleHostsEndRule() throws {
        let page = try String(contentsOf: root.appendingPathComponent("Resources/GameKit/apple/LampPage.swift"), encoding: .utf8)
        let dir = try folder()
        let main = """
            import Foundation
            \(try block(page, from: "struct LampVoiceEnd {"))
            let EMPTY: [Double] = []
            func play(_ name: String, _ levels: [Double]) {
                var end = LampVoiceEnd(); var t = 0.0; var i = 0
                while t < 20 {
                    if i < levels.count { end.heard(level: levels[i], top: levels[i] * 1.4, at: t); i += 1 }
                    t += 0.04
                    if let e = end.ended(at: t) { print("\\(name)|\\(e)|\\(t)"); return }
                }
                print("\\(name)|none|\\(t)")
            }
            \(driverLines { "play(\($0))" })
            """
        try main.write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try run("/usr/bin/xcrun", ["swiftc", "-O", dir.appendingPathComponent("main.swift").path, "-o", dir.appendingPathComponent("end").path])
        check(try run(dir.appendingPathComponent("end").path, []), "Apple")
    }

    /// Lamp's own Kotlin compiler (the one Android builds download), or a skip where Android was never set up.
    private func kotlin() throws -> (java: String, compile: [String], stdlib: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let java = home.appendingPathComponent("Library/Developer/Lamp/Android/jdk/Contents/Home/bin/java").path
        let cache = home.appendingPathComponent("Library/Caches/Lamp/gradle/caches/modules-2/files-2.1")
        func jar(_ group: String, _ name: String) -> String? {
            let dir = cache.appendingPathComponent("\(group)/\(name)")
            guard let versions = try? FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() else { return nil }
            for v in versions.reversed() {
                let e = FileManager.default.enumerator(atPath: dir.appendingPathComponent(v).path)
                while let f = e?.nextObject() as? String {
                    if f.hasSuffix(".jar") && !f.contains("sources") { return dir.appendingPathComponent(v).appendingPathComponent(f).path }
                }
            }
            return nil
        }
        let names = [("org.jetbrains.kotlin", "kotlin-compiler-embeddable"), ("org.jetbrains.kotlin", "kotlin-stdlib"),
                     ("org.jetbrains.kotlin", "kotlin-script-runtime"), ("org.jetbrains.kotlin", "kotlin-reflect"),
                     ("org.jetbrains.kotlin", "kotlin-daemon-embeddable"), ("org.jetbrains", "annotations"),
                     ("org.jetbrains.kotlinx", "kotlinx-coroutines-core-jvm")]
        let jars = names.compactMap { jar($0.0, $0.1) }
        guard FileManager.default.isExecutableFile(atPath: java), jars.count == names.count else {
            throw XCTSkip("Android's tools aren't set up on this Mac (open an Android app in Lamp to download them).")
        }
        return (java, jars, jars[1])
    }

    private func runKotlin(_ source: String) throws -> String {
        let k = try kotlin()
        let dir = try folder()
        try source.write(to: dir.appendingPathComponent("Main.kt"), atomically: true, encoding: .utf8)
        try run(k.java, ["-cp", k.compile.joined(separator: ":"), "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler", "-no-reflect",
                         "-classpath", k.stdlib, "-d", dir.appendingPathComponent("out").path, dir.appendingPathComponent("Main.kt").path])
        return try run(k.java, ["-cp", dir.appendingPathComponent("out").path + ":" + k.stdlib, "MainKt"])
    }

    func testTheAndroidHostsEndRule() throws {
        let gateway = GameAndroid.pageGateway
        let out = try runKotlin("""
            \(try block(gateway, from: "class LampVoiceEnd {"))
            val EMPTY = doubleArrayOf()
            fun play(name: String, levels: DoubleArray) {
                val end = LampVoiceEnd(); var t = 0.0; var i = 0
                while (t < 20) {
                    if (i < levels.size) { end.heard(levels[i], levels[i] * 1.4, t); i += 1 }
                    t += 0.04
                    end.ended(t)?.let { println("$name|$it|$t"); return }
                }
                println("$name|none|$t")
            }
            fun main() {
            \(driverLines { "play(\($0.replacingOccurrences(of: "[", with: "doubleArrayOf(").replacingOccurrences(of: "]", with: ")")))" })
            }
            """)
        check(out, "Android")
    }

    func testAnAndroidRecordingEndsOnItsOwnWithoutWaitingForAudio() throws {
        let gateway = GameAndroid.pageGateway
        let out = try runKotlin("""
            \(try block(gateway, from: "class LampVoiceEnd {"))
            \(try block(gateway, from: "class LampVoiceTake("))
            fun main() {
                // A: no audio comes. It's cancelled, and B starts straight after: A ends at once, as cancelled.
                val a = LampVoiceTake("a")
                var aEnded = ""
                val worker = Thread { aEnded = a.run({ _, _ -> 0 }, System::nanoTime) { _, _ -> } }
                worker.start()
                Thread.sleep(100)
                a.stop("cancelled")
                val b = LampVoiceTake("b")
                val began = System.nanoTime()
                worker.join(2000)
                println("a|$aEnded|${(System.nanoTime() - began) / 1e9}")
                println("b|${b.stopAs ?: "open"}|0")
                // Audio that stops coming: the clock ends it, at six seconds with nothing heard.
                var clock = 0L
                val stalled = LampVoiceTake("c").run({ _, _ -> clock += 100_000_000L; 0 }, { clock }) { _, _ -> }
                println("stalled|$stalled|${clock / 1e9}")
                // A read that fails is a failure.
                val failed = try { LampVoiceTake("d").run({ _, _ -> -3 }, System::nanoTime) { _, _ -> }; "no" } catch (e: java.io.IOException) { "thrown" }
                println("failed|$failed|0")
            }
            """)
        let lines = Dictionary(uniqueKeysWithValues: out.split(separator: "\n").map { l -> (String, [String]) in
            let p = l.split(separator: "|").map(String.init); return (p[0], Array(p.dropFirst()))
        })
        XCTAssertEqual(lines["a"]?.first, "cancelled", out)
        XCTAssertLessThan(Double(lines["a"]?.last ?? "9") ?? 9, 0.5, "ended without waiting for audio")
        XCTAssertEqual(lines["b"]?.first, "open", "the next recording's own stop is untouched")
        XCTAssertEqual(lines["stalled"]?.first, "nothing", out)
        XCTAssertEqual(Double(lines["stalled"]?.last ?? "0") ?? 0, 6, accuracy: 0.2)
        XCTAssertEqual(lines["failed"]?.first, "thrown", out)
    }
}

import Foundation
import AVFoundation
import SwiftUI

final class GuitarListener: ObservableObject {
    @Published var feedback = "Play the chord when you’re ready."
    @Published var quality = 0
    @Published var running = false
    @Published var error: String?
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label:"guitar.analysis",qos:.userInitiated)
    private var lastAnalysis = Date.distantPast
    private var lastAccepted = Date.distantPast
    private var previousEnergy = 0.0
    private var armed = true
    private var stable = 0
    private var cancelled = false
    private let detector = ChordDetector()
    private var acceptedChroma = [Double](repeating:0,count:12)
    private var acceptedTarget = ""
    private var quietFloor = 0.0001
    private var stableSince: Date?
    private var sessionID = UUID()
    @Published var inputLevel = 0.0
    @Published var heard = ""
    var target = "G"
    var onChord: (() -> Void)?
    static let voicings: [String:[Int]] = ["G":[43,47,50,55,59,67],"C":[48,52,55,60,64],"D":[50,57,62,66],"Em":[40,47,52,55,59,64],"Am":[45,52,57,60,64],"E":[40,47,52,56,59,64],"A":[45,52,57,61,64],"Dm":[50,57,62,65],"F":[41,48,53,57,60,65],"D7":[50,57,60,66],"G7":[43,47,50,55,59,65],"Cadd9":[48,52,55,62,67],"B7":[47,51,57,59,66]]
    func start() async {
        guard !running else { return }
        cancelled = false
        error = nil
        sessionID = UUID()
        let session = sessionID
        stable = 0; stableSince = nil; armed = true
        lastAccepted = .distantPast; acceptedTarget = ""
        queue.sync { detector.reset() }
        guard await AVCaptureDevice.requestAccess(for:.audio) else {
            error = "Microphone access is off. Listening needs your permission."; return
        }
        guard !cancelled, session == sessionID else { return }
        do {
            let input = engine.inputNode
            let format = input.outputFormat(forBus:0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                error = "No audio input found. Connect a microphone or interface."; return
            }
            input.installTap(onBus:0,bufferSize:4096,format:format) { [weak self] buffer,_ in
                guard let self, let channels = buffer.floatChannelData else { return }
                // Interfaces often put the guitar on input 2. Choose the loudest
                // channel instead of silently listening to an empty input 1.
                let count = Int(buffer.frameLength)
                var selected = 0
                var strongest = 0.0
                for c in 0..<Int(buffer.format.channelCount) {
                    var energy = 0.0
                    for i in 0..<count { energy += Double(channels[c][i]*channels[c][i]) }
                    if energy > strongest { strongest = energy; selected = c }
                }
                let channel = channels[selected]
                let samples = Array(UnsafeBufferPointer(start:channel,count:Int(buffer.frameLength)))
                let rate = buffer.format.sampleRate
                self.queue.async { self.analyze(samples,rate:rate,session:session) }
            }
            try engine.start()
            DispatchQueue.main.async { self.running = true }
        } catch {
            engine.inputNode.removeTap(onBus:0)
            self.error = error.localizedDescription
        }
    }
    func stop() {
        cancelled = true
        sessionID = UUID()
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus:0) }
        running = false
    }
    private func analyze(_ samples:[Float],rate:Double,session:UUID) {
        let energy = sqrt(samples.reduce(0.0) {$0 + Double($1 * $1)} / Double(max(1,samples.count)))
        let chroma = detector.consume(samples,sampleRate:rate)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionID == session, self.running else { return }
            self.inputLevel = min(1,sqrt(energy)*3)
            if let chroma { self.judge(chroma,energy:energy) }
        }
    }
    private func judge(_ chroma:[Double],energy:Double) {
        guard running else { return }
        defer { previousEnergy = energy }
        if energy < quietFloor * 1.5 { quietFloor = max(0.00003,quietFloor*0.9+energy*0.1) }
        if energy < max(0.00025,quietFloor*2.5) {
            armed = true; stable = 0; stableSince = nil; quality = 0; heard = ""
            feedback = "Listening — give the strings a gentle strum."
            return
        }
        let since = Date().timeIntervalSince(lastAccepted)
        if energy > max(0.0003,previousEnergy) * 1.35, since > 0.4 { armed = true }
        // A genuine change in harmony can advance without requiring a pause.
        if target != acceptedTarget, since > 0.35 {
            let difference = zip(chroma,acceptedChroma).reduce(0.0) {$0+abs($1.0-$1.1)}
            if difference > 0.6 { armed = true }
        }
        guard armed, since > 0.35 else { return }
        guard let voicing = Self.voicings[target] else {
            feedback = "Listening doesn’t recognize \(target) yet. Try the supported open-chord arrangement."
            quality = 1; return
        }
        let expected = Set(voicing.map {$0 % 12})
        let ranked = Self.voicings.map { (name:$0.key,score:ChordDetector.score(chroma,notes:$0.value)) }.sorted {$0.score > $1.score}
        guard let best = ranked.first, best.score > 0.3 else {
            stableSince = nil; quality = 0; heard = "Unclear"; feedback = "I hear sound, but no clear chord yet. Try a slow strum."; return
        }
        let score = ChordDetector.score(chroma,notes:voicing)
        let present = expected.filter { chroma[$0] > 0.12 }
        let root = voicing[0] % 12
        let third = (root + (target.contains("m") && !target.contains("maj") ? 3 : 4)) % 12
        let definingNotes = chroma[root] > 0.10 && chroma[third] > 0.10
        let close = score >= 0.72 && score >= best.score - 0.035 && definingNotes
        let good = close && present.count == expected.count && score >= 0.83
        heard = best.score > 0.7 ? best.name : "Unclear"
        quality = good ? 2 : 1
        if good { feedback = "That’s it. The guitar agrees." }
        else if close { feedback = "Close enough. Let those notes ring a little longer." }
        else {
            let names = ["C","C♯","D","E♭","E","F","F♯","G","A♭","A","B♭","B"]
            if score < best.score - 0.08 && best.score > 0.78 {
                feedback = "That sounds closer to \(best.name). Take your time finding \(target)."
            } else if let missing = expected.subtracting(present).sorted().first {
                feedback = "The \(names[missing]) is quiet; try letting each string ring."
            } else { feedback = "Nearly there. Try one slow, even strum." }
        }
        if close { if stableSince == nil { stableSince = Date() } }
        else { stableSince = nil }
        if let began = stableSince, Date().timeIntervalSince(began) >= 0.22 {
            stableSince = nil; stable = 0; armed = false; lastAccepted = Date()
            acceptedChroma = chroma; acceptedTarget = target
            onChord?()
        }
    }
    deinit { engine.stop() }
}

import AVFoundation

/// The vehicles' sounds, made on the fly: a two-tone horn, a wailing siren and the ice cream truck's tune.
final class Synth: @unchecked Sendable {
    static let shared = Synth()

    var horn = false
    var siren = false
    /// The engine of whatever you're driving: on, how fast it's turning (0 idle to 1 redline), how hard it's
    /// working (0 to 1), and how deep it sounds (1 a car, lower for trucks and trains, higher for sports cars).
    var motor = false
    var motorRPM: Double = 0
    var motorLoad: Double = 0
    var motorPitch: Double = 1
    private var mp: Double = 0, mr: Double = 0, rpmNow: Double = 0, motorLevel: Double = 0
    private var bang: Double = 0
    private var bangPhase: Double = 0
    private var noise: UInt32 = 12345

    /// A crunch, from 0 (a tap) to 1 (a big one).
    func crash(_ strength: Float) {
        start()
        bang = max(bang, Double(min(1, strength)))
    }
    private var thumpLevel: Double = 0, thumpPhase: Double = 0
    private var oofAt: Int = -1, oofLevel: Double = 0, oofPhase: Double = 0

    /// A dull knock: a scrape along a wall, a nudge into a car or a pole.
    func thud(_ strength: Float) {
        start()
        thumpLevel = max(thumpLevel, Double(min(1, strength)))
    }

    /// Someone hit: a thump and a short grunt falling in pitch.
    func oof(_ strength: Float) {
        start()
        thud(strength)
        oofAt = 0
        oofLevel = Double(min(1, strength))
    }

    private var crackAt: Int = -1, crackLevel: Double = 0, creakPhase: Double = 0

    /// Wood giving way: a few sharp snaps and a groan.
    func crack(_ strength: Float) {
        start()
        crackAt = 0
        crackLevel = Double(min(1, strength))
    }

    private var clangAt: Int = -1, clangLevel: Double = 0, clangPhases: [Double] = [0, 0, 0, 0]

    /// Metal struck: a pole or sign hit or hitting the ground.
    func clang(_ strength: Float) {
        start()
        clangAt = 0
        clangLevel = Double(min(1, strength))
    }

    /// A hydrant's spray: 0 silent to 1 right beside it (set every frame).
    var spray: Double = 0
    private var sprayNow: Double = 0, sprayLow: Double = 0

    private var tuneAt: Int = -1           // sample the tune is up to, -1 when not playing
    private var engine: AVAudioEngine?
    private var rate: Double = 44100
    private var t: Int = 0
    private var p1: Double = 0, p2: Double = 0, ps: Double = 0, pt: Double = 0

    // "Pop Goes the Weasel"-ish, in hertz and beats.
    private let tune: [(Double, Double)] = [(523, 1), (523, 0.5), (587, 0.5), (587, 1), (659, 0.5), (784, 0.5), (659, 1),
                                            (523, 1), (523, 0.5), (587, 0.5), (587, 1), (659, 1.5), (523, 1.5),
                                            (523, 1), (523, 0.5), (587, 0.5), (587, 1), (659, 0.5), (784, 0.5), (659, 1),
                                            (880, 1), (587, 1), (698, 1), (659, 1), (523, 2)]
    private let beat = 0.22

    func playTune() { start(); tuneAt = 0 }
    var tunePlaying: Bool { tuneAt >= 0 }

    /// Starts the audio the first time a sound is wanted.
    func start() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        rate = format.sampleRate > 0 ? format.sampleRate : 44100
        let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let node = AVAudioSourceNode(format: mono) { [unowned self] _, _, frames, list in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for i in 0..<Int(frames) { out[i] = self.sample() }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = 0.6
        try? engine.start()
        self.engine = engine
    }

    private func sample() -> Float {
        t += 1
        var s: Double = 0
        let dt = 1 / rate
        if horn {
            // Two flat tones a third apart, squared off.
            p1 += 2 * .pi * 392 * dt; p2 += 2 * .pi * 494 * dt
            s += (sin(p1) > 0 ? 0.11 : -0.11) + (sin(p2) > 0 ? 0.09 : -0.09)
        }
        // The engine: a buzzy firing note that follows the revs, with a rumble under it; fades in and out.
        motorLevel += ((motor ? 1 : 0) - motorLevel) * dt * 4
        if motorLevel > 0.001 {
            rpmNow += (motorRPM - rpmNow) * dt * 6
            let f = (32 + 120 * rpmNow) * motorPitch
            mp += 2 * .pi * f * dt
            mr += 2 * .pi * f * 0.5 * dt
            let saw = (mp / (2 * .pi)).truncatingRemainder(dividingBy: 1) * 2 - 1
            noise = noise &* 1664525 &+ 1013904223
            let n = Double(noise >> 8) / Double(1 << 24) * 2 - 1
            // Quiet ticking over at idle, louder with revs and throttle.
            let level = (0.003 + 0.01 * rpmNow + 0.0125 * motorLoad * rpmNow) * motorLevel
            s += level * (0.55 * saw + 0.45 * sin(mr) + 0.15 * n * (0.3 + motorLoad))
        }
        if siren {
            // A wail rising and falling every three seconds.
            let f = 950 + 450 * sin(2 * .pi * Double(t) * dt / 3)
            ps += 2 * .pi * f * dt
            s += 0.16 * sin(ps) + 0.05 * sin(2 * ps)
        }
        if bang > 0.001 {
            // Noise for the crunch, a low thump under it, dying away.
            noise = noise &* 1664525 &+ 1013904223
            let n = Double(noise >> 8) / Double(1 << 24) * 2 - 1
            bangPhase += 2 * .pi * 55 * dt
            s += bang * (0.45 * n + 0.35 * sin(bangPhase))
            bang *= exp(-dt * 7)
        }
        if thumpLevel > 0.001 {
            thumpPhase += 2 * .pi * (70 + 60 * thumpLevel) * dt
            noise = noise &* 1664525 &+ 1013904223
            let n = Double(noise >> 8) / Double(1 << 24) * 2 - 1
            s += thumpLevel * (0.4 * sin(thumpPhase) + 0.12 * n)
            thumpLevel *= exp(-dt * 16)
        }
        if oofAt >= 0 {
            let at = Double(oofAt) * dt
            if at < 0.28 {
                // A voice-ish buzz sliding down, shaped like "oof".
                let f = 260 - 420 * at
                oofPhase += 2 * .pi * f * dt
                let saw = (oofPhase / (2 * .pi)).truncatingRemainder(dividingBy: 1) * 2 - 1
                let env = min(1, at * 40) * (1 - at / 0.28)
                s += oofLevel * env * (0.12 * saw + 0.1 * sin(oofPhase))
                oofAt += 1
            } else { oofAt = -1 }
        }
        if crackAt >= 0 {
            let at = Double(crackAt) * dt
            if at < 0.6 {
                noise = noise &* 1664525 &+ 1013904223
                let n = Double(noise >> 8) / Double(1 << 24) * 2 - 1
                var snaps = 0.0
                for t0 in [0.0, 0.045, 0.1, 0.19, 0.31] where at >= t0 { snaps += exp(-(at - t0) * 70) }
                creakPhase += 2 * .pi * (95 - 50 * at) * dt
                let saw = (creakPhase / (2 * .pi)).truncatingRemainder(dividingBy: 1) * 2 - 1
                s += crackLevel * (0.55 * n * min(1, snaps) + 0.08 * saw * max(0, 1 - at / 0.6))
                crackAt += 1
            } else { crackAt = -1 }
        }
        if clangAt >= 0 {
            let at = Double(clangAt) * dt
            if at < 0.9 {
                // A few out-of-tune partials, the high ones dying first.
                let partials: [(Double, Double, Double)] = [(310, 0.10, 4), (787, 0.08, 6), (1433, 0.06, 9), (2290, 0.04, 14)]
                for (k, p) in partials.enumerated() {
                    clangPhases[k] += 2 * .pi * p.0 * dt
                    s += clangLevel * p.1 * sin(clangPhases[k]) * exp(-at * p.2)
                }
                clangAt += 1
            } else { clangAt = -1 }
        }
        sprayNow += (spray - sprayNow) * dt * 3
        if sprayNow > 0.001 {
            // Rushing water: soft noise, its harshest edge taken off.
            noise = noise &* 1664525 &+ 1013904223
            let n = Double(noise >> 8) / Double(1 << 24) * 2 - 1
            sprayLow += (n - sprayLow) * 0.35
            s += sprayNow * 0.09 * sprayLow
        }
        if tuneAt >= 0 {
            var at = Double(tuneAt) * dt
            var playing = false
            for (f, beats) in tune {
                let d = beats * beat
                if at < d {
                    pt += 2 * .pi * f * dt
                    let env = min(1, at * 60) * max(0, 1 - at / d * 0.6)
                    s += 0.14 * env * (sin(pt) + 0.3 * sin(3 * pt))
                    playing = true
                    break
                }
                at -= d
            }
            tuneAt = playing ? tuneAt + 1 : -1
        }
        return Float(s)
    }
}

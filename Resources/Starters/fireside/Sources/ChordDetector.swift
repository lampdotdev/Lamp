import Foundation
import Accelerate

/// Harmonic matching pursuit separates fundamentals from their overtones before
/// comparing chords. Pure signal processing, also used by the offline fixture checks.
final class ChordDetector {
    private let size = 4096
    private let rate = 11025.0
    private let setup = vDSP_create_fftsetup(12, FFTRadix(kFFTRadix2))!
    private var pending: [Float] = []
    private var sampleRemainder: [Float] = []
    private var previousRate = 0.0
    private var resamplePosition = 0.0
    deinit { vDSP_destroy_fftsetup(setup) }

    func reset() { pending.removeAll(); sampleRemainder.removeAll(); previousRate = 0; resamplePosition = 0 }

    func consume(_ samples: [Float], sampleRate: Double) -> [Double]? {
        guard sampleRate > 0 else { return nil }
        if previousRate != sampleRate { reset(); previousRate = sampleRate }
        // Linear resampling preserves duration across arbitrary tap buffer sizes.
        sampleRemainder.append(contentsOf:samples)
        let step = sampleRate / rate
        var position = resamplePosition
        // Both samples around the position must be here; the last one waits for the next buffer.
        while Int(position) + 1 < sampleRemainder.count {
            let i = Int(position)
            let fraction = Float(position - Double(i))
            pending.append(sampleRemainder[i] * (1-fraction) + sampleRemainder[i+1] * fraction)
            position += step
        }
        let consumed = Int(position)
        if consumed > 0 { sampleRemainder.removeFirst(min(consumed,sampleRemainder.count)) }
        resamplePosition = position - Double(consumed)
        guard pending.count >= size else { return nil }
        let frame = Array(pending.suffix(size))
        pending = Array(pending.suffix(size / 2))
        return features(frame)
    }

    func features(_ samples: [Float]) -> [Double] {
        var real = [Float](repeating:0,count:size)
        var imaginary = real
        let mean = samples.reduce(0,+) / Float(max(1,samples.count))
        for i in 0..<min(size,samples.count) {
            real[i] = (samples[i]-mean) * Float(0.5-0.5*cos(2 * .pi * Double(i)/Double(size-1)))
        }
        real.withUnsafeMutableBufferPointer { r in
            imaginary.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp:r.baseAddress!,imagp:im.baseAddress!)
                vDSP_fft_zip(setup,&split,1,12,FFTDirection(FFT_FORWARD))
            }
        }
        var spectrum = (0..<size/2).map { sqrt(Double(real[$0]*real[$0]+imaginary[$0]*imaginary[$0])) }
        let band = spectrum[25..<min(1500,spectrum.count)]
        let powerMean = band.reduce(0.0) {$0+$1*$1} / Double(band.count)
        let geometricPower = exp(band.reduce(0.0) {$0+log(max(1e-20,$1*$1))} / Double(band.count))
        // Broadband noise can accidentally fit three pitch classes after pursuit.
        // Reject it before normalization amplifies a few random spectral peaks.
        guard powerMean > 1e-12, geometricPower / powerMean < 0.42 else {
            return [Double](repeating:0,count:12)
        }
        // Remove the broadband floor, rather than treating room noise as notes.
        let sorted = spectrum[25..<min(1500,spectrum.count)].sorted()
        let floor = sorted[sorted.count/2] * 1.8
        spectrum = spectrum.map { max(0,$0-floor) }
        let maximum = spectrum.max() ?? 0
        guard maximum > 0.00001 else { return [Double](repeating:0,count:12) }
        spectrum = spectrum.map { $0 / maximum }
        var chroma = [Double](repeating:0,count:12)
        // Greedily explain a spectrum with complete harmonic stacks. A strong
        // B overtone of low E should not become a separately played B string.
        for _ in 0..<10 {
            var bestScore = 0.0
            var bestMidi = 0
            var bestBins: [(Int,Double)] = []
            for midi in 40...76 {
                let frequency = 440 * pow(2,Double(midi-69)/12)
                var bestTuningScore = 0.0
                var bestTuningBins: [(Int,Double)] = []
                for cents in [-30.0,0,30] {
                    let tuned = frequency * pow(2,cents/1200)
                    var bins: [(Int,Double)] = []
                    var score = 0.0
                    var weightTotal = 0.0
                    for harmonic in 1...6 {
                        let bin = Int((tuned * Double(harmonic) / rate * Double(size)).rounded())
                        guard bin > 1, bin+1 < spectrum.count else { continue }
                        let strongest = (bin-1...bin+1).max { spectrum[$0] < spectrum[$1] }!
                        let weight = 1 / pow(Double(harmonic),0.85)
                        score += spectrum[strongest] * weight
                        weightTotal += weight * weight
                        bins.append((strongest,weight))
                    }
                    // Fundamental evidence prevents subharmonic hallucinations.
                    let fundamental = bins.first.map { spectrum[$0.0] } ?? 0
                    score = score / max(0.001,weightTotal) * min(1,fundamental * 5)
                    if score > bestTuningScore { bestTuningScore = score; bestTuningBins = bins }
                }
                if bestTuningScore > bestScore { bestScore = bestTuningScore; bestMidi = midi; bestBins = bestTuningBins }
            }
            guard bestScore > 0.06 else { break }
            chroma[bestMidi % 12] += bestScore
            for (bin,weight) in bestBins {
                for neighbor in max(0,bin-1)...min(spectrum.count-1,bin+1) {
                    spectrum[neighbor] = max(0,spectrum[neighbor]-bestScore*weight)
                }
            }
        }
        let peak = chroma.max() ?? 0
        return peak > 0 ? chroma.map {$0 / peak} : chroma
    }

    static func score(_ chroma: [Double], notes: [Int]) -> Double {
        let expected = Set(notes.map {$0 % 12})
        let total = chroma.reduce(0,+)
        guard total > 0 else { return 0 }
        let inside = expected.reduce(0.0) {$0+chroma[$1]}
        let coverage = expected.reduce(0.0) {$0+min(1,chroma[$1]/0.22)} / Double(expected.count)
        return inside / total * 0.65 + coverage * 0.35
    }
}

import SwiftUI

/// The microphone's loudness over the last few seconds, as bars that move from right to left.
struct LevelMeter: View {
    let levels: [Float]
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(isActive ? Color.red.opacity(0.75) : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: max(3, CGFloat(levels[index]) * 40))
            }
        }
        .frame(height: 42)
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue(isActive ? "\(Int((levels.last ?? 0) * 100)) percent" : "Not recording")
    }
}

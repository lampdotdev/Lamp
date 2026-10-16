import SwiftUI

/// The big ring: it fills clockwise as the phase goes by, with the time left in the middle.
struct FocusRing: View {
    var progress: Double
    var time: String
    var phase: Phase
    var isPaused: Bool

    private let lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.of(phase).opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Color.of(phase).gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            VStack(spacing: 2) {
                Text(time)
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: time)
                Text(isPaused ? "Paused" : phase.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phase.title), \(time) left\(isPaused ? ", paused" : "")")
    }
}

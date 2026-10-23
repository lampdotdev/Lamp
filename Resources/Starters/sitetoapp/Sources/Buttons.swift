import SwiftUI

/// The catalog's main button: a glossy sky-to-violet capsule that lifts on hover and presses in.
struct GlowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlowButton(configuration: configuration)
    }

    private struct GlowButton: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                .padding(.horizontal, 26)
                .padding(.vertical, 13)
                .background {
                    ZStack {
                        Capsule().fill(Theme.gradient)
                        // A soft sheen across the top half, like glass catching light.
                        Capsule()
                            .fill(LinearGradient(colors: [.white.opacity(hovering ? 0.38 : 0.28), .white.opacity(0)],
                                                 startPoint: .top, endPoint: .center))
                            .padding(1.5)
                        Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    }
                }
                .shadow(color: Theme.violet.opacity(hovering ? 0.5 : 0.35), radius: hovering ? 18 : 12, y: hovering ? 8 : 5)
                .shadow(color: Theme.sky.opacity(0.25), radius: 3, y: 1)
                .scaleEffect(configuration.isPressed ? 0.96 : (hovering ? 1.03 : 1))
                .brightness(configuration.isPressed ? -0.05 : 0)
                .opacity(enabled ? 1 : 0.5)
                .animation(.spring(duration: 0.28, bounce: 0.4), value: hovering)
                .animation(.spring(duration: 0.18), value: configuration.isPressed)
                .onHover { hovering = $0 }
                .contentShape(Capsule())
        }
    }
}

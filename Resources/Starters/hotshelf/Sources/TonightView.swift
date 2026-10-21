import SwiftUI

/// "What's cooking tonight?" at the foot of the shelf, and the note that comes with the bottle it lifts.
struct TonightBar: View {
    @EnvironmentObject var shelf: Shelf
    @SceneStorage("tonight.dish") private var dish = ""
    @FocusState private var focused: Bool

    private let ink = Look.current.ink

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if let pick = shelf.pick, let bottle = shelf.bottle(pick.bottleID) {
                note(pick, bottle)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let error = shelf.pickError {
                Text(error)
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(Look.current.ink)
                    .background(Capsule().fill(.black.opacity(0.4)))
            }
            field
        }
        .padding(.bottom, 22)
        .padding(.trailing, 22)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: Look.current.askSymbol).foregroundStyle(Look.current.accent)
            TextField("Tonight", text: $dish, prompt: Text(Look.current.askPrompt).foregroundStyle(Look.current.ink.opacity(0.5)))
                .foregroundStyle(Look.current.ink)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .focused($focused)
                .onSubmit { shelf.pickForTonight(dish) }
            if shelf.picking {
                ProgressView().controlSize(.small)
            } else {
                Button { shelf.pickForTonight(dish) } label: {
                    Image(systemName: Look.current.askButtonSymbol)
                        .foregroundStyle(Look.current.wall)
                        .padding(7)
                        .background(Circle().fill(Look.current.ink))
                }
                .buttonStyle(.plain)
                .disabled(dish.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Pick a bottle for it")
                .accessibilityLabel("Pick a bottle")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(width: 360)
        .background(Capsule().fill(.black.opacity(0.42)))
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(focused ? 0.45 : 0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }

    private func note(_ pick: Pick, _ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(Look.current.display.text("Tonight: \(bottle.name)"))
                    .font(Look.current.display(15))
                Spacer()
                Capsule().fill(heatColor(bottle.heat)).frame(width: 22, height: 5)
            }
            Text(pick.why)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Another One") { shelf.pickForTonight(pick.dish, another: true) }
                    .disabled(shelf.picking)
                Spacer()
                Button("Put It Back") { shelf.putBack() }
                Button("Using It") {
                    shelf.update({ var b = bottle; b.lastUsedAt = Date(); return b }())
                    shelf.putBack()
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(ink)
            .padding(.top, 4)
        }
        .foregroundStyle(ink)
        .padding(16)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.5)))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
    }
}

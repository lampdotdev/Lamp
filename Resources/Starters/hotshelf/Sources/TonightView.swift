import SwiftUI

/// "What's cooking tonight?" at the foot of the shelf, and the note that comes with the bottle it lifts.
struct TonightBar: View {
    @EnvironmentObject var shelf: Shelf
    @SceneStorage("tonight.dish") private var dish = ""
    @FocusState private var focused: Bool

    private let paper = Zine.cream
    private let ink = Zine.navy

    var body: some View {
        VStack(spacing: 12) {
            if let pick = shelf.pick, let bottle = shelf.bottle(pick.bottleID) {
                note(pick, bottle)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let error = shelf.pickError {
                Text(error)
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(Zine.navy)
                    .background(Capsule().fill(Zine.cream))
            }
            field
        }
        .padding(.bottom, 22)
        .padding(.horizontal, 30)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "frying.pan").foregroundStyle(Zine.red)
            TextField("Tonight", text: $dish, prompt: Text("What's cooking tonight?").foregroundStyle(Zine.navy.opacity(0.45)))
                .foregroundStyle(Zine.navy)
                .textFieldStyle(.plain)
                .font(.system(.title3, design: .rounded))
                .focused($focused)
                .onSubmit { shelf.pickForTonight(dish) }
            if shelf.picking {
                ProgressView().controlSize(.small)
            } else {
                Button { shelf.pickForTonight(dish) } label: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Circle().fill(Zine.red))
                }
                .buttonStyle(.plain)
                .disabled(dish.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Pick a bottle for it")
                .accessibilityLabel("Pick a bottle")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(maxWidth: 520)
        .background(Capsule().fill(Zine.cream))
        .overlay(Capsule().strokeBorder(Zine.navy, lineWidth: focused ? 2 : 1.4))
        .background(Capsule().fill(Zine.pinkShadow).offset(x: 3, y: 5))
    }

    private func note(_ pick: Pick, _ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tonight: \(bottle.name)")
                    .font(Hand.font(20))
                Spacer()
                Capsule().fill(heatColor(bottle.heat)).frame(width: 22, height: 5)
            }
            Text(pick.why)
                .font(.system(.body, design: .serif))
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
        .frame(maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: 4).fill(paper)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Zine.navy, lineWidth: 1.4))
                .background(RoundedRectangle(cornerRadius: 4).fill(Zine.pinkShadow).offset(x: 4, y: 6))
        )
        .rotationEffect(.degrees(-1.2))
        .environment(\.colorScheme, .light)
    }
}

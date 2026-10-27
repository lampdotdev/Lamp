import AppKit
import SwiftUI

/// Do It for Me as it goes, in every setup window that offers it (a TV's, a device integration's): what's done, what
/// Lamp is doing, and what the person does now on the device. Drawn from plain values (`GuidedSetup.state`), so the
/// gallery shows it as people see it.
struct SetupGuideView: View {
    struct State: Equatable {
        var lines: [GuidedSetup.Line] = []
        var ask: String?
        var button: String?
        var link: Link?
        var failure: String?

        struct Link: Equatable { var title: String; var url: URL }
    }

    let state: State
    let confirm: () -> Void
    let retry: () -> Void
    /// Back to the steps in words, whatever the device does; nil once the steps have handed the device back.
    var doItMyself: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(state.lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    switch line.state {
                    case .doing: ProgressView().controlSize(.mini)
                    case .done: Image(systemName: "checkmark").foregroundStyle(.green)
                    case .note: Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    }
                    Text(line.text).foregroundStyle(line.state == .done ? .secondary : .primary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let ask = state.ask {
                Text(ask).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            if let failure = state.failure {
                Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if let button = state.button { Button(button, action: confirm) }
                if let link = state.link { Button(link.title) { NSWorkspace.shared.open(link.url) } }
                if state.failure != nil { Button("Try Again", action: retry) }
                if let doItMyself { Button("Do It Myself", action: doItMyself) }
            }
        }
    }
}

/// The button that starts a guide, with the guide's own line on what Lamp does and what the person does.
struct DoItForMeRow: View {
    let offer: String?
    let start: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Do It for Me", action: start)
            if let offer { Text(offer).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

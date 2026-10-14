import SwiftUI

/// The card an app with a widget has in its chat: the one thing left for the person to do, which nobody can
/// do for them, and then the plain fact that it's done.
///
/// Only the person can put a widget on the desktop, and macOS gives Lamp no way to open the place it's done
/// from. So the card says how, in a line, and stops saying it once the widget is there: the app the widget
/// belongs to may ask macOS whether it's placed, and leaves the answer where Lamp reads it
/// (`LampWidgetPlacement` in LampSupport.swift).
enum WidgetCard {
    /// Whether the app's widget is on the desktop or in Notification Center, as the app last found it.
    static func isPlaced(_ project: LampProject) -> Bool {
        let file = Runtime.macFolder(project).appendingPathComponent("widget-placed")
        return (try? String(contentsOf: file, encoding: .utf8))?.trimmed == "1"
    }

    /// Forgotten before a build's install: the widget may be another one now, and the app says afresh.
    static func forget(_ project: LampProject) {
        try? FileManager.default.removeItem(at: Runtime.macFolder(project).appendingPathComponent("widget-placed"))
    }

    /// One card per chat, however many builds the app has: it's added when the app first has a widget.
    static func isNeeded(after lines: [LogLine]) -> Bool { !lines.contains { $0.kind == .widget } }

    /// A card stays in the chat's record, but is only shown while the app has a widget: once the widget is
    /// taken away there's nothing to add, and saying how would send the person looking for it.
    static func isShown(for project: LampProject) -> Bool {
        project.platform.hasIOS ? Template.hasHomeScreenWidget(project) : Template.hasWidget(project)
    }

    /// Whether to run a widget-only app out of sight to ask if its widget is placed, on coming back to Lamp.
    /// Asked whatever the last answer was: a widget that was placed can be taken off the desktop again, and
    /// the app that would notice has quit.
    static func asksAgain(hasCard: Bool, widgetOnly: Bool, busy: Bool) -> Bool { hasCard && widgetOnly && !busy }

    static func title(_ name: String) -> String { "\(name)’s widget" }

    static func status(_ name: String, placed: Bool) -> String {
        placed ? "On your desktop" : "Right-click the desktop, choose Edit Widgets, then pick \(name)."
    }

    /// On an iPhone or iPad, where only the person can add a widget to the home screen and iOS doesn't say
    /// whether they have, so the card always says how.
    static func phoneStatus(_ name: String) -> String {
        "Touch and hold the Home Screen, tap Edit, then Add Widget, and pick \(name)."
    }
}

struct WidgetCardView: View {
    /// The folder of the app whose chat this is.
    let dir: URL
    @ObservedObject private var store = Store.shared

    var body: some View {
        if let project = store.projects.first(where: { $0.dir == dir }) {
            let placed = store.placedWidgets.contains(project.id)
            // Laid out like the setup card: the same badge, title and one gray line.
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: placed ? "checkmark" : "widget.small")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(shape.fill(LinearGradient(colors: placed ? [Color.green.opacity(0.85), Color.green]
                                                          : [Color.accentColor.opacity(0.85), Color.accentColor],
                                                          startPoint: .top, endPoint: .bottom)))
                    .overlay(shape.strokeBorder(.black.opacity(0.08)))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(WidgetCard.title(project.name)).font(.headline)
                    Text(project.platform.hasIOS ? WidgetCard.phoneStatus(project.name) : WidgetCard.status(project.name, placed: placed))
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        }
    }
}

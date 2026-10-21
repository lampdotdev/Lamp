import SwiftUI

/// One thing to do: ticked off with the circle, opened with a click to show where in the email it came from and to
/// put it in Reminders or Calendar.
struct TodoRow: View {
    @EnvironmentObject var backpack: Backpack
    let todo: Todo
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    withAnimation(.snappy) { backpack.toggle(todo) }
                } label: {
                    Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(todo.isDone ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(todo.isDone ? "Mark as not done" : "Mark as done")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: todo.kind.symbol)
                            .foregroundStyle(todo.kind.color)
                            .frame(width: 18)
                            .help(todo.kind.name)
                        Text(todo.title)
                            .strikethrough(todo.isDone)
                            .foregroundStyle(todo.isDone ? .secondary : .primary)
                            .lineLimit(isExpanded ? nil : 2)
                        Spacer(minLength: 4)
                        if let due = Format.due(todo) {
                            Text(due)
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(Format.isLate(todo) ? Color.red : Color.secondary)
                        }
                    }
                    Text(byline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if isExpanded { details.padding(.leading, 30) }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering || isExpanded ? Color.primary.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleExpanded)
        .onHover { hovering = $0 }
        .contextMenu { actions }
    }

    private var byline: String {
        [todo.child, Sender.name(todo.from)].compactMap { $0 }.joined(separator: " · ")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let quote = todo.quote {
                Text("“\(quote)”")
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(todo.subject) · \(todo.received.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            HStack(spacing: 8) {
                if todo.reminderID != nil {
                    Label("In Reminders", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Add to Reminders", systemImage: "bell") { Task { await backpack.addToReminders(todo) } }
                }
                if todo.due != nil {
                    if todo.eventID != nil {
                        Label("In Calendar", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Add to Calendar", systemImage: "calendar.badge.plus") { Task { await backpack.addToCalendar(todo) } }
                    }
                }
                Spacer()
                Button {
                    withAnimation(.snappy) { backpack.delete(todo) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete")
                .accessibilityLabel("Delete")
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder private var actions: some View {
        Button(todo.isDone ? "Mark as Not Done" : "Mark as Done") { backpack.toggle(todo) }
        Divider()
        if todo.reminderID == nil {
            Button("Add to Reminders") { Task { await backpack.addToReminders(todo) } }
        }
        if todo.due != nil && todo.eventID == nil {
            Button("Add to Calendar") { Task { await backpack.addToCalendar(todo) } }
        }
        Divider()
        Button("Delete", role: .destructive) { backpack.delete(todo) }
    }
}

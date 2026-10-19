import SwiftUI
import AppKit

struct BugReportScene: Scene {
    var body: some Scene {
        Window("Report a Bug", id: "bug-report") {
            BugReportView().environmentObject(Store.shared)
        }
        .defaultSize(width: 640, height: 680)
    }
}

struct BugReportView: View {
    @EnvironmentObject private var store: Store
    @State private var report = ""
    @State private var copied = false
    @State private var confirmNewReport = false
    @State private var delivery = BugReportDelivery.State.ready

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Report a bug").font(.title2.bold())
                Spacer()
                Button("New Report…") { confirmNewReport = true }
                    .disabled(delivery.isSending)
            }
            Text("Send this report to the Lamp team via lamp.dev.")
            Text("Describe the problem below. Review and edit the entire report before clicking Send. Nothing is sent automatically. If sending fails, copy or share it with the person who invited you.")
                .foregroundStyle(.secondary)
            TextEditor(text: $report)
                .disabled(delivery.isSending)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .accessibilityLabel("Bug report")
            Text("Includes versions, your selected engine, and activity labels. Log text, keys, chat and app code are left out unless you add them yourself.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .top) {
                if delivery.isSending { ProgressView().controlSize(.small) }
                Text(report.utf8.count > BugReportDelivery.maxBytes
                     ? "The report is too long to send (limit 16 KB). Shorten it, or copy or share it."
                     : delivery.message)
                    .font(.callout)
                    .foregroundStyle(deliveryFailed ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if copied { Text("Copied.").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                ShareLink(item: report) { Text("Share…") }
                    .disabled(report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(report, forType: .string)
                }
                .disabled(report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(delivery.isSending ? "Sending…" : "Send") {
                    let reviewed = report
                    delivery = .sending
                    Task {
                        do {
                            try await BugReportDelivery.send(reviewed)
                            delivery = .sent
                        } catch { delivery = .failed(error.localizedDescription) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(delivery.isSending || delivery == .sent || report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || report.utf8.count > BugReportDelivery.maxBytes)
            }
        }
        .padding(24)
        .frame(minWidth: 580, minHeight: 560)
        .onAppear {
            // Keep an unfinished report when the window is brought forward again.
            if report.isEmpty { report = snapshot() }
        }
        .onChange(of: report) { copied = false; delivery = .ready }
        .alert("Start a new report?", isPresented: $confirmNewReport) {
            Button("Start New Report", role: .destructive) {
                report = snapshot()
                copied = false
                delivery = .ready
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Copy or share this report first if you want to keep it. Starting a new report replaces your text and captures the current diagnostics.")
        }
    }

    private var deliveryFailed: Bool {
        if case .failed = delivery { return true }
        return false
    }

    private func snapshot() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let selected = store.selected
        let lines = selected.map { store.logs[$0.id] ?? [] } ?? []
        let activity = lines.suffix(20).map { line -> BugReport.Activity in
            switch line.kind {
            case .user: .request
            case .agent, .ask, .progress: .reply
            case .status, .noted, .drawIcon, .widget, .result, .iphoneSetup: .status
            case .error: .error
            case .detail: .detail
            case .tool: .tool
            case .summary: .summary
            case .needsKey, .offer: .setupOffered
            }
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return BugReport.draft(
            version: info["CFBundleShortVersionString"] as? String ?? "Unknown",
            build: info["CFBundleVersion"] as? String ?? "Unknown",
            macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            engine: Builder.engine == .pi ? "Built-in agent (pi)" : Builder.engine.title,
            isDev: Edition.isDev, hasSelection: selected != nil,
            isBusy: selected.map { store.busy.contains($0.id) } ?? false,
            activity: activity, lastError: lines.last(where: { $0.kind == .error })?.text)
    }
}

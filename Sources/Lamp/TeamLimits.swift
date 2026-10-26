import Foundation

/// What Apple won't sign for a free Apple account's team (a Personal Team, `PhoneTools.xcodeFreeTeams`), as Lamp declares
/// it in capabilities.json. Found by asking Xcode for each (`FreeTeamProbeLiveTests`): every one of these is refused with
/// "Personal development teams … do not support the … capability", while HealthKit, HomeKit and app groups sign.
enum TeamLimits {
    /// The entitlement each is signed with, and the name the person and the agent know it by.
    static let refused: [(entitlement: String, name: String)] = [
        ("com.apple.developer.icloud-services", "iCloud"), ("com.apple.developer.nfc.readersession.formats", "NFC"),
        ("com.apple.developer.siri", "Siri"), ("com.apple.developer.weatherkit", "Apple's weather"),
        ("com.apple.developer.usernotifications.time-sensitive", "Time Sensitive notifications"),
    ]

    /// The names of what `project` is signed with for `platform` that a free team can't sign, in `refused`'s order: read
    /// from the entitlements Lamp signs that platform's copy with, so a capability only the iPhone takes (Time Sensitive
    /// notifications) never holds up an app for both on the Mac.
    static func refused(in project: LampProject, for platform: Destination = .ios) -> [String] {
        let plist = Template.Capabilities.load(project).entitlementsPlist(for: project, platform: platform)
        return refused.filter { plist.contains("<key>\($0.entitlement)</key>") }.map(\.name)
    }

    /// "iCloud", "iCloud and Siri", "NFC, Siri and Apple's weather".
    static func list(_ names: [String]) -> String {
        names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    /// Why `project` can't be signed for `place` (the person's phone, this Mac) with `team`, or nil when it can: it
    /// declares what Apple signs only for a paid team, and `team` is a free one. Said at the build, never before a
    /// request: a message always reaches the agent, which is how the person takes those out again.
    static func problem(for project: LampProject, on place: String, platform: Destination = .ios, team: String, free: Set<String>) -> String? {
        guard free.contains(team) else { return nil }
        let names = refused(in: project, for: platform)
        guard !names.isEmpty else { return nil }
        return "\(project.name) uses \(list(names)), which Apple allows only with a paid Apple Developer membership. Your Apple account is a free one, so Lamp can't put the app on \(place). Choose a simulator under Try On to keep working, or ask Lamp to take \(names.count == 1 ? "it" : "them") out."
    }

    /// For the agent, when the team is a free one: what it mustn't declare, and what the person's phone allows.
    static let agentLine = "The person's Apple team is a free one (a Personal Team): Apple won't sign "
        + list(refused.map(\.name)) + " for it, so don't declare them in capabilities.json; if the wish needs one, say so plainly and make the app without it "
        + "(HealthKit, HomeKit and widgets are fine). An app it signs opens for seven days, until Play puts it on the phone again, and a phone takes three such apps."
}

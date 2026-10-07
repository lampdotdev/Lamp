import Foundation

/// Interpret the tool's whole failure, including nested causes. A missing profile is often just the last
/// consequence of an account, quota or capability problem; it must not hide that earlier explanation.
struct PhoneFailure: LocalizedError {
    enum Stage: String { case build, install, launch }
    enum Cause: String {
        case account, team, authentication, developerTrust, launchSecurity, appLimit, idLimit, expiredProfile
        case capability, certificate, locked, unreachable, developerMode, signing, build, install, launch
    }
    let stage: Stage
    let cause: Cause
    let output: String
    var errorDescription: String? { message }

    init(stage: Stage, output: String) {
        self.stage = stage
        self.output = output
        let text = output.lowercased()
        func has(_ phrases: String...) -> Bool { phrases.contains { text.contains($0) } }
        if has("device is locked", "device was not, or could not be, unlocked", "unlock the device", "device locked") {
            cause = .locked
        } else if has("maximum number of apps for free development", "maximum number of installed apps") {
            cause = .appLimit
        } else if has("maximum app id limit", "10 app ids every 7 days") {
            cause = .idLimit
        } else if has("profile has expired", "profile is expired", "profile expired", "provisioningprofileexpired") ||
                    text.range(of: #"provisioning profile(?: \"[^\"\n]*\"| '[^'\n]*')? (?:has expired|expired on|expiration date has passed)"#, options: .regularExpression) != nil {
            cause = .expiredProfile
        } else if has("invalid code signature, inadequate entitlements", "invalid code signature, inadequate entitlements or its profile") {
            // Apple's security refusal lists alternatives. It does not establish which one happened.
            cause = .launchSecurity
        } else if has("developer is not trusted", "untrusted developer", "profile has not been explicitly trusted") {
            cause = .developerTrust
        } else if (has("personal development teams", "personal team") && has("do not support", "does not support")) ||
                    (has("capability", "entitlement") && has("not supported", "does not support", "doesn't support", "not permitted")) {
            cause = .capability
        } else if has("no account for team", "not a member of", "does not belong to the selected team") {
            cause = .team
        } else if has("no accounts", "add a new account in accounts settings") {
            cause = .account
        } else if has("session has expired", "unable to log in", "invalid credentials", "authentication failed") {
            cause = .authentication
        } else if has("no signing certificate", "certificate has been revoked", "certificate has expired", "private key", "errsecinternalcomponent", "user interaction is not allowed", "cssmerr_tp", "keychain is locked") {
            cause = .certificate
        } else if has("developer mode is disabled", "developer mode is not enabled") {
            cause = .developerMode
        } else if has("device was not found", "device is not connected", "device is disconnected", "unable to find a device matching", "unable to find a destination matching the provided destination specifier", "failed to establish a connection", "operation timed out", "connection timed out") {
            cause = .unreachable
        } else if stage == .build && text.range(of: #"\.swift:\d+(?::\d+)?: error:"#, options: .regularExpression) != nil {
            cause = .build
        } else if has("provisioning profile", "no profiles for", "code signing", "command codesign failed", "signing for") {
            cause = .signing
        } else {
            cause = switch stage { case .build: .build; case .install: .install; case .launch: .launch }
        }
    }

    private var capabilityName: String? {
        guard let range = output.range(of: #"(?i)(?:do not|does not|doesn't) support (?:the )?[^.\n]{1,160} capabilit(?:y|ies)"#, options: .regularExpression) else { return nil }
        let phrase = String(output[range])
        return phrase.replacingOccurrences(of: #"(?i)^(?:do not|does not|doesn't) support (?:the )?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i) capabilit(?:y|ies)$"#, with: "", options: .regularExpression)
    }

    var message: String {
        switch cause {
        case .account:
            "Xcode couldn't find an Apple account for signing. Open Xcode → Settings → Accounts and sign in, then Retry."
        case .team:
            "Xcode can't sign for the Apple team selected in Lamp. Choose your account's team in Lamp → Settings → Building → Experimental, or add that team's account in Xcode → Settings → Accounts, then Retry."
        case .authentication:
            "Xcode couldn't use your Apple account. Open Xcode → Settings → Accounts and complete any sign-in or account notices, then Retry."
        case .developerTrust:
            "The phone hasn't trusted this app's developer yet. On the phone, open Settings → General → VPN & Device Management, choose the developer under Developer App, and tap Trust or Verify. Keep the phone online, then Retry."
        case .launchSecurity:
            "The phone refused to open the app. It may need you to trust the developer: on the phone, open Settings → General → VPN & Device Management, choose the developer under Developer App, and tap Trust or Verify. Keep the phone online, then Retry. If it is already trusted, the app's signature or permissions may be invalid; check your team and signing certificates in Xcode."
        case .appLimit:
            "The phone has reached the free-account limit of 3 development apps. Remove a development app you no longer need from the phone, then Retry. Removing an app deletes its data."
        case .idLimit:
            "Your free Apple account has reached its limit of 10 app IDs in 7 days. Wait for earlier registrations to expire, then Retry, or choose a paid developer team in Lamp's settings. Deleting apps from the phone doesn't free these registrations."
        case .expiredProfile:
            "The app's permission to run on the phone has expired. Free-account signing lasts 7 days. Connect and unlock the phone, then Retry to sign and install it again."
        case .capability:
            "Your Apple account can't sign for \(capabilityName ?? "a feature this app uses"). Ask Lamp to remove that feature, or choose a developer team that supports it in Lamp's settings, then Retry. Apple's reason is under Agent Details."
        case .certificate:
            "Xcode couldn't use a signing certificate or its private key. In Xcode → Settings → Accounts, select your team and open Manage Certificates to check your Apple Development certificate. Unlock your login keychain and allow signing access if asked, then Retry."
        case .locked:
            "The phone is locked. Unlock it with its passcode and keep it unlocked, then Retry."
        case .unreachable:
            "Lamp couldn't reach the phone. Plug it in with a data cable and unlock it, then Retry."
        case .developerMode:
            "Turn on Developer Mode on the phone in Settings → Privacy & Security → Developer Mode. Restart, unlock it, and confirm Turn On, then Retry."
        case .signing:
            "Xcode couldn't sign the app for the phone. Check your selected team and any signing notices in Xcode → Settings → Accounts, then Retry. Apple's reason is under Agent Details."
        case .build:
            "The app couldn't be built for the phone. The reason is under Agent Details. Retry, or ask Lamp to fix the phone build if it fails again."
        case .install:
            "The app couldn't be installed on the phone. The reason is under Agent Details. Check the phone and Retry."
        case .launch:
            "Lamp couldn't confirm that the app opened on the phone. Keep the phone connected and unlocked, then Retry. The reason is under Agent Details."
        }
    }
}

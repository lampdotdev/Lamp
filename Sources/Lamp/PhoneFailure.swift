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
            "Xcode can't use the Apple team selected in Lamp. In Lamp → Settings → Building, choose a team that belongs to your Apple account. Or sign in with an account for the selected team in Xcode → Settings → Accounts. Then click Retry."
        case .authentication:
            "Xcode couldn't sign in with your Apple account. Open Xcode → Settings → Accounts and follow any prompts to sign in again. Then click Retry."
        case .developerTrust:
            "The phone hasn't trusted this app's developer yet. On the phone, open Settings → General → VPN & Device Management, choose the developer under Developer App, and tap Trust or Verify. Keep the phone online, then Retry."
        case .launchSecurity:
            "The phone wouldn't open the app. On the phone, open Settings → General → VPN & Device Management. If the app's developer appears under Developer App, select it and tap Trust or Verify. Keep the phone online, then click Retry. If the developer is already trusted or isn't listed, open Agent Details to see Apple's error."
        case .appLimit:
            "Your free Apple account allows up to 3 development apps on the phone. Delete one you no longer need, then click Retry. Deleting it also deletes its data."
        case .idLimit:
            "You've reached your free Apple account's limit of 10 app IDs in 7 days. Wait until Apple lets you register another, then click Retry. Or choose a team with a paid Apple Developer membership in Lamp → Settings → Building. Deleting apps from the phone won't reset this limit."
        case .expiredProfile:
            "This app needs to be renewed before it can run on the phone. Connect and unlock the phone, then click Retry to reinstall it. Apps installed with a free Apple account need renewing every 7 days."
        case .capability:
            "Your Apple team doesn't support \(capabilityName ?? "a feature this app uses"). Ask Lamp to remove that feature, or choose a team that supports it in Lamp → Settings → Building. Then click Retry. Open Agent Details to see Apple's explanation."
        case .certificate:
            "Xcode couldn't sign the app. If your Mac asks to unlock the login keychain or allow access, follow the prompt, then click Retry. If it still fails, open Agent Details to see the error. You can find your Apple Development certificates in Xcode → Settings → Accounts: select your account and team, then open Manage Certificates."
        case .locked:
            "The phone is locked. Unlock it with its passcode and keep it unlocked, then Retry."
        case .unreachable:
            "Lamp couldn't reach the phone. Plug it in with a data cable and unlock it, then Retry."
        case .developerMode:
            "On the phone, open Settings → Privacy & Security → Developer Mode and turn it on. Restart the device when asked, unlock it, and tap Turn On to confirm. Then click Retry."
        case .signing:
            "Xcode couldn't sign the app for the phone. Make sure the team selected in Lamp → Settings → Building belongs to your Apple account. In Xcode → Settings → Accounts, follow any prompts to sign in again, then click Retry. If it still fails, open Agent Details to see Apple's error."
        case .build:
            "The app couldn't be built for the phone. Click Retry. If it fails again, ask Lamp to fix it and include the error from Agent Details."
        case .install:
            "The app couldn't be installed on the phone. Keep it connected and unlocked, then click Retry. If it still fails, open Agent Details to see the error."
        case .launch:
            "Lamp couldn't confirm that the app opened on the phone. Keep the phone connected and unlocked, then Retry. The reason is under Agent Details."
        }
    }
}

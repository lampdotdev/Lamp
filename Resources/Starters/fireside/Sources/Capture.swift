import AppKit

enum SongCapture {
    static func browserURL() throws -> URL {
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let script: String
        switch bundle {
        case "com.apple.Safari": script = "tell application id \"com.apple.Safari\" to get URL of current tab of front window"
        case "com.google.Chrome": script = "tell application id \"com.google.Chrome\" to get URL of active tab of front window"
        case "company.thebrowser.Browser": script = "tell application id \"company.thebrowser.Browser\" to get URL of active tab of front window"
        default: throw NSError(domain:"Capture",code:1,userInfo:[NSLocalizedDescriptionKey:"Open a tab in Safari, Chrome, or Arc, then press the shortcut."])
        }
        var error: NSDictionary?
        let result = NSAppleScript(source:script)?.executeAndReturnError(&error)
        if let error { throw NSError(domain:"Capture",code:2,userInfo:[NSLocalizedDescriptionKey:error.description]) }
        guard let value = result?.stringValue,let url = URL(string:value),["https","http"].contains(url.scheme ?? "") else {
            throw NSError(domain:"Capture",code:3,userInfo:[NSLocalizedDescriptionKey:"No readable webpage is open."])
        }
        return url
    }
}

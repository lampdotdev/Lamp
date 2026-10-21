import Foundation

/// What Lamp tells an app about itself and Lamp is in the app's Info.plist (`Template.installValues`), read at launch
/// by LampSupport's `LampInstall` and the widget's `LampWidget.value`. A test that compiles Lamp's support code into a
/// plain program gives it the same: an Info.plist linked into the program's own `__info_plist` section, which
/// `Bundle.main` reads for a program that isn't in a bundle.
enum InstallValues {
    /// Writes an Info.plist holding `values` as `LampInstall` into `folder`, and gives the swiftc flags that link it in.
    static func linkerFlags(_ values: [String: String], in folder: URL, named name: String = "Info.plist") throws -> String {
        let plist = ["LampInstall": values] as [String: Any]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return "-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker \"\(url.path)\""
    }
}

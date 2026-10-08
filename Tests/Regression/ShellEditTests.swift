import XCTest
@testable import Lamp

/// A shell command that edits files the way the file tools do is declined, not put to the user.
final class ShellEditTests: XCTestCase {
    func testEditsAreRecognised() {
        XCTAssertTrue(Privacy.editsFilesThroughShell(#"cd "/Users/matt/Library/Application Support/Lamp/Apps/powermeter/Sources"; sed -n 848,852p LampSupport.swift; sed -i '' 's/a/b/' PowerMonitor.swift; grep -n 'x' AppSampler.swift"#))
        XCTAssertTrue(Privacy.editsFilesThroughShell("cd Sources && python3 - <<'EOF'\np='ContentView.swift'\nEOF"))
        XCTAssertTrue(Privacy.editsFilesThroughShell("cat > ../icon.json <<'EOF'\n{}\nEOF"))
        XCTAssertTrue(Privacy.editsFilesThroughShell("echo 'x' >> Sources/App.swift"))
        XCTAssertTrue(Privacy.editsFilesThroughShell("perl -pi -e 's/a/b/' Sources/App.swift"))
    }

    func testReadsBuildsAndGitAreNot() {
        XCTAssertFalse(Privacy.editsFilesThroughShell("sed -n 10,20p Sources/App.swift"))
        XCTAssertFalse(Privacy.editsFilesThroughShell("grep -rn 'LampStore' Sources"))
        XCTAssertFalse(Privacy.editsFilesThroughShell("swift build 2>&1 | tail -20"))
        XCTAssertFalse(Privacy.editsFilesThroughShell("git status --porcelain"))
        XCTAssertFalse(Privacy.editsFilesThroughShell("ls Sources > /dev/null"))
        XCTAssertFalse(Privacy.editsFilesThroughShell("gh repo clone owner/name .lamp/reference/name -- --depth 1"))
    }

    /// A `>` inside quotes is text, not a redirect.
    func testQuotedAnglesAreNotRedirects() {
        XCTAssertFalse(Privacy.editsFilesThroughShell(#"git log --grep="a > b""#))
        XCTAssertFalse(Privacy.editsFilesThroughShell(#"python3 -c "print(4 > 3)""#))
        XCTAssertFalse(Privacy.editsFilesThroughShell(#"grep -n 'x >> y' Sources/App.swift"#))
        XCTAssertFalse(Privacy.editsFilesThroughShell(#"echo "a \> b""#))
        XCTAssertTrue(Privacy.editsFilesThroughShell(#"echo "a > b" > Sources/Notes.txt"#))
        XCTAssertFalse(Privacy.editsFilesThroughShell("swift build &> /dev/null"))
    }
}

import XCTest
@testable import Lamp

/// A command that goes into one of the app's folders and comes back hasn't left the app's folder; anything
/// that might have still counts as leaving it.
final class CommandFolderTests: XCTestCase {
    private var root: URL!
    private var project: LampProject!

    override func setUpWithError() throws {
        // Not a temporary folder: those are open to the agent, so a step out of the app wouldn't show.
        root = URL(fileURLWithPath: "/Users/Shared/lamp-tests-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("Apps/tally")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources/Views"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Apps/notes"), withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("APP.md"))
        project = LampProject(id: "tally", name: "Tally", exe: "Tally", dir: dir)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func outside(_ command: String) -> Bool { Privacy.reachesOutside(command, project: project) }

    /// The command from the report: two inline scripts, one in Sources and one back in the app's folder.
    func testGoingIntoSourcesAndBackStaysInside() {
        XCTAssertFalse(outside("""
        cd "\(project.dir.path)/Sources"; python3 - <<'EOF'
        p='PowerMonitor.swift'; s=open(p).read()
        a="        if isSettling { return measured }"
        assert a in s; s=s.replace(a,"x"); open(p,'w').write(s)
        EOF
        cd ..; python3 - <<'EOF'
        p='APP.md'; s=open(p).read()
        open(p,'w').write(s)
        EOF
        """))
        XCTAssertFalse(outside("cd Sources; grep -c 'func ' *.swift; cd ..; cat APP.md | head -30"))
        XCTAssertFalse(outside("cd Sources && sed -n 1,5p App.swift 2>&1 | head -3; cd .."))
        XCTAssertFalse(outside("cd Sources/Views; ls; cd ..; ls; cd ..; ls"))
        XCTAssertFalse(outside("cd Sources\ncd Views\nls\ncd ..\ncd .."))
    }

    func testGoingUpFromTheAppsFolderLeavesIt() {
        XCTAssertTrue(outside("cd ..; ls"))
        XCTAssertTrue(outside("cd Sources; cd ..; cd ..; ls notes"))
        XCTAssertTrue(outside("cd Sources/Views; cd ..; cd ..; cd ..; ls"))
        XCTAssertTrue(outside("cd Sources; cat ../../notes/.lamp/token"))
        XCTAssertTrue(outside("cd Sources; ls ..; cd .."))
    }

    /// Every way the `cd` going in might not have happened, or the shell might be somewhere else by the
    /// time it goes back up.
    func testACdThatMightNotHappenCountsForNothing() {
        for command in [
            "cd Missing; cd ..; cat notes/.lamp/token",
            "false && cd Sources; cd ..; ls",
            "true || cd Sources; cd ..; ls",
            "(cd Sources); cd ..; ls",
            "cd Sources | true; cd ..; ls",
            "cd Sources & cd ..; ls",
            "echo $(cd Sources); cd ..; ls",
            "echo `cd Sources`; cd ..; ls",
            "if false; then cd Sources; fi; cd ..; ls",
            "f() { cd Sources; }; cd ..; ls",
            "{ cd Sources; }; cd ..; ls",
            "echo cd Sources; cd ..; ls",
            "cat <<'EOF' >/dev/null\ncd Sources\nEOF\ncd ..; ls",
            "cat <<EOF\ncd Sources\ncd ..; ls",
            "echo 'cd Sources\n'; cd ..; ls",
            "# cd Sources\ncd ..; ls",
            "rm -rf Sources; cd Sources; cd ..; ls",
            "mv Sources Other; cd Sources; cd ..; cat notes/.lamp/token",
            "d=Sources; cd $d; cd ..; ls",
            "cd Sour*; cd ..; ls",
            "cd Sources extra; cd ..; ls",
            "cd Sources; eval 'cd /'; cd ..; ls",
            "cd Sources; source go.sh; cd ..; ls",
            "cd Sources; . go.sh; cd ..; ls",
            "cd Sources; cd -; cd ..; ls",
            "cd Sources; cd; cd ..; ls",
            "cd Sources; X=1 cd /; cd ..; ls",
            "cd Sources; true | cd /; cd ..; ls",
            "cd Sources; pushd /; cd ..; ls",
            "cd Sources; alias ls='cd /'; ls; cd ..; cat x",
            "cd \(root.path)/Apps/notes; cd ..; ls",
            "cd /; cd ..; ls",
        ] {
            XCTAssertTrue(outside(command), command)
        }
    }

    /// A link inside the app's folder that leads out of it is where it leads.
    func testAFolderThatIsALinkOutCountsAsOutside() throws {
        try FileManager.default.createSymbolicLink(at: project.dir.appendingPathComponent("Linked"), withDestinationURL: root.appendingPathComponent("Apps/notes"))
        XCTAssertTrue(outside("cd Linked; cd ..; ls"))
    }

    func testStepsAreReadAsTheShellRunsThem() {
        let steps = Privacy.steps(of: "cd 'My Sources'; grep -n \"a;b\" x.swift 2>&1 | head -3 && echo done")
        XCTAssertEqual(steps?.map { $0.words.map(\.text) }, [["cd", "My Sources"], ["grep", "-n", "a;b", "x.swift", "2"], ["head", "-3"], ["echo", "done"]])
        XCTAssertEqual(steps?.map(\.alone), [true, false, false, false])
        XCTAssertEqual(Privacy.steps(of: "cd $HOME")?.first?.words.last?.literal, false)
        XCTAssertEqual(Privacy.steps(of: "cd \"$HOME\"")?.first?.words.last?.literal, false)
        XCTAssertEqual(Privacy.steps(of: "cd '$HOME'")?.first?.words.last?.literal, true)
        XCTAssertNil(Privacy.steps(of: "cd Sources; (ls)"))
        XCTAssertNil(Privacy.steps(of: "echo 'unclosed"))
    }
}

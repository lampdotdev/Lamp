import XCTest
@testable import Lamp

/// Install Command-Line Tool… replaces only what's safe to replace, and never links to a copy of Lamp that's going away.
final class CommandLineToolTests: XCTestCase {
    func testAFolderIsNeverTakenForTheCommandAndAPassingCopyIsRefused() throws {
        let fm = FileManager.default
        let place = fm.temporaryDirectory.appendingPathComponent("lamp-command-\(UUID().uuidString)")
        try fm.createDirectory(at: place, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: place) }
        let launcher = place.appendingPathComponent("launcher")
        try Data("#!/bin/sh\n".utf8).write(to: launcher)
        let command = place.appendingPathComponent("lamp").path
        XCTAssertEqual(CommandLineTool.found(at: command, launcher: launcher), .nothing)
        try fm.createDirectory(atPath: command, withIntermediateDirectories: false)
        XCTAssertEqual(CommandLineTool.found(at: command, launcher: launcher), .folder)
        try fm.removeItem(atPath: command)
        try fm.createSymbolicLink(atPath: command, withDestinationPath: launcher.path)
        XCTAssertEqual(CommandLineTool.found(at: command, launcher: launcher), .ours)
        XCTAssertTrue(CommandLineTool.isPassing("/Volumes/Lamp/Lamp.app"))
        XCTAssertTrue(CommandLineTool.isPassing("/private/var/folders/x/AppTranslocation/ABC/d/Lamp.app"))
        XCTAssertFalse(CommandLineTool.isPassing("/Applications/Lamp.app"))
    }
}

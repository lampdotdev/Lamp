#!/usr/bin/env python3
"""Replay certificate-team lookup with disposable certificates and optional read-only real metadata."""
from pathlib import Path
import subprocess
import sys
source = Path('Sources/Lamp/Devices.swift').read_text()
def block(marker, source=source):
    start=source.index(marker); brace=source.index('{',start);depth=1;end=brace+1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end]
# Devices.xcodeTeams hands over to PhoneTools, where the read of Xcode's signed-in teams lives now.
tools = Path('Sources/Lamp/PhoneTools.swift').read_text()
folder=Path(sys.argv[1])
for name,subject in [('different-id','/CN=Apple Development: Test Person (CLIENT0001)/OU=TEAM000001/O=Test'),
                     ('missing-team','/CN=Apple Development: Test Person (CLIENT0001)/O=Test'),
                     ('invalid-team','/CN=Apple Development: Test Person (CLIENT0001)/OU=NOT-A-TEAM/O=Test')]:
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj',subject,
                    '-keyout',str(folder/(name+'.key')),'-out',str(folder/(name+'.pem'))],check=True,capture_output=True)
    subprocess.run(['openssl','x509','-in',str(folder/(name+'.pem')),'-outform','der','-out',str(folder/(name+'.der'))],check=True)
text='import Foundation\nimport Security\nimport CryptoKit\n'
text+='enum PhoneTools {\n'+block('static func xcodeTeams()', tools)+'\n}\n'
text+='enum Devices {\n'
text+='\n'.join(block(marker) for marker in ['static func xcodeTeams()', 'static func knownTeams()', 'static func certificateTeam('])+'\n}\n'
text += r'''
enum Preflight {
    struct Device { let name = "Test iPhone"; let paired = true; var developerMode: Bool }
    static func xcodeTeams() -> [(id: String, name: String)] { [("TEAM000001", "Test Team")] }
''' + block('static func problem(') + '\n}\n'
text+=r'''
@main struct TeamReplay {
    static func check(_ value: Bool, _ label: String) {
        if !value { fatalError("FAIL: \(label)") }
        print("PASS: \(label)")
    }
    static func certificate(_ path: URL) throws -> SecCertificate {
        let data = try Data(contentsOf: path)
        return SecCertificateCreateWithData(nil, data as CFData)!
    }
    static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let different = try certificate(folder.appendingPathComponent("different-id.der"))
        let team = Devices.certificateTeam(different)
        check(team?.id == "TEAM000001", "certificate organizational unit supplies the real Team ID")
        check(team?.id != "CLIENT0001", "developer ID in the common name is never offered as a Team ID")
        check(team?.name == "Test Person", "display name omits the developer ID suffix")
        let missing = try certificate(folder.appendingPathComponent("missing-team.der"))
        check(Devices.certificateTeam(missing) == nil, "no organizational unit means no guessed Team ID")
        let invalid = try certificate(folder.appendingPathComponent("invalid-team.der"))
        check(Devices.certificateTeam(invalid) == nil, "invalid organizational unit is not offered as a Team ID")
        let expected = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: "Tests/PhoneInstall/Fixtures/messages.json")))
        check(Preflight.problem(Preflight.Device(developerMode: false), team: "TEAM000001") == expected["deviceDeveloperMode"],
              "Developer Mode preflight keeps the device name and approved confirmation steps")
        check(Preflight.problem(Preflight.Device(developerMode: true), team: "OTHER00001") == expected["deviceTeam"],
              "unavailable selected team points to Lamp's team settings")
        if CommandLine.arguments.count > 2 {
            let confirmed = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let actual = await Devices.knownTeams()
            check(actual.contains { $0.id == confirmed }, "read-only real team lookup includes the Xcode-confirmed Personal Team")
            var result: CFTypeRef?
            let query: [String: Any] = [kSecClass as String: kSecClassCertificate,
                                       kSecMatchSubjectContains as String: "Apple Development",
                                       kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnRef as String: true]
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let certificates = result as? [SecCertificate] else { fatalError("Real certificate unavailable") }
            check(certificates.contains { Devices.certificateTeam($0)?.id == confirmed },
                  "real certificate subject team matches Xcode's test-project team")
            for certificate in certificates {
                if let summary = SecCertificateCopySubjectSummary(certificate) as String?,
                   let range = summary.range(of: #"[A-Z0-9]{10}(?=\)$)"#, options: .regularExpression),
                   let real = Devices.certificateTeam(certificate), real.id != String(summary[range]) {
                    check(!actual.contains { $0.id == String(summary[range]) },
                          "real developer-name suffix is no longer an invalid team choice")
                }
            }
        }
        print("Certificate-team checks passed. Only public certificate metadata was read.")
    }
}
'''
(folder/'TeamReplay.swift').write_text(text)

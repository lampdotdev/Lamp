import CryptoKit
import Foundation

/// Lamp's starters as repositories on GitHub (`Starters.account`, one each): each starter made into a wish the way the
/// desk makes one and laid out as Put on GitHub lays a wish out (`GitHubRepo.stage`: the shared file's contents with
/// its checks, Lamp's own files so `./build.sh` builds it, a README, an MIT license), so it opens with File → Open from
/// GitHub…, and a copy on someone's desk takes the latest of it (Update from GitHub…) and sends changes back to it
/// (Send Changes Back…). `scripts/publish-starters.sh` runs this, puts each tree up and writes the address and commit
/// into the starter's starter.md, which every copy made from then on carries on its chain (`Starters.copy`).
///
/// The tree is the same every time for the same starter, so a starter that didn't change makes no new commit: its
/// identity is derived from the starter (never a random one), its export time is fixed, and the shared file isn't in
/// it (a zip differs every time it's made; the tree is what Lamp opens).
enum StarterRepos {
    static let commandLineFlag = "--stage-starter-repos"

    /// `Lamp --stage-starter-repos <folder>`, with `STAGE_STARTERS=1`: each starter's tree into `<folder>/<starter>`,
    /// then quits.
    static func stageFromCommandLine() -> Never {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: commandLineFlag), index + 1 < arguments.count else {
            FileHandle.standardError.write(Data("Usage: Lamp \(commandLineFlag) <folder>\n".utf8))
            exit(2)
        }
        let out = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        // The starters hold none of the person's keys, and reading them would ask the keychain from a command line.
        Sharing.knownSecrets = { _ in [] }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-starter-repos-\(UUID().uuidString)")
        var failed = false
        for starter in Starters.bundled {
            do {
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                let tree = try stage(starter, in: root)
                let to = out.appendingPathComponent(starter.folder.lastPathComponent)
                try? fm.removeItem(at: to)
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                try fm.copyItem(at: tree, to: to)
                print("Staged \(starter.name)")
            } catch {
                FileHandle.standardError.write(Data("Couldn't stage \(starter.name): \(error.localizedDescription) \((error as? LocalizedError)?.recoverySuggestion ?? "")\n".utf8))
                failed = true
            }
            try? fm.removeItem(at: root)
        }
        exit(failed ? 1 : 0)
    }

    /// The repository a starter goes in: "RooCodeInc/lamp-starter-newyork".
    static func repo(of starter: Starters.Starter) -> String {
        Starters.account + "/" + Starters.repositoryName(of: starter.folder.lastPathComponent)
    }

    /// One starter's tree, in a work folder under `root`.
    static func stage(_ starter: Starters.Starter, in root: URL) throws -> URL {
        let fm = FileManager.default
        let project = try Template.draft(name: starter.name, platform: starter.kind, in: root)
        try Template.fill(project)
        try Starters.copy(starter, into: project)
        try Template.writeOwnedFiles(for: project)
        Sharing.setIdentity(identity(of: starter), of: project)
        let repo = repo(of: starter)
        let staged = try GitHubRepo.stage(project, repo: repo, link: nil)
        let tree = staged.folder
        // The tree alone, not the shared file beside it.
        for file in try fm.contentsOfDirectory(at: tree, includingPropertiesForKeys: nil) where file.pathExtension == "lampapp" {
            try fm.removeItem(at: file)
        }
        // The chain: what the starter is based on, and the starter itself, named where it lives. The commit is the
        // one this tree becomes, which whoever opens it gets from the repository (`RepoImport.naming`).
        let based = Credits.read(starter.folder.appendingPathComponent(Credits.file)) ?? Credits()
        let chain = based.remixed(from: Credits.Remix(name: starter.name, starter: starter.folder.lastPathComponent, url: GitHubRepo.url(repo)))
        try chain.encoded().write(to: tree.appendingPathComponent(Credits.file), options: .atomic)
        // Made at no particular time, so an unchanged starter is an unchanged tree.
        let manifestURL = tree.appendingPathComponent("lamp-app.json")
        if var manifest = try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] {
            manifest["exportedAt"] = "2026-01-01T00:00:00Z"
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: manifestURL)
        }
        let (root, parts) = Sharing.layout(of: project)
        let build = GitHubRepo.Build(alone: root.platform.target.recipe.buildsAlone, app: root.platform.target.identity.name, others: !parts.isEmpty)
        try Data(GitHubRepo.readme(for: project, credits: chain, open: Publish.OpenInLamp(link: nil, file: nil), build: build, repo: repo).utf8)
            .write(to: tree.appendingPathComponent("README.md"))
        if GitHubRepo.canOfferLicense(chain) {
            try Data(GitHubRepo.mitLicense(holder: "Roo Code, Inc.").utf8).write(to: tree.appendingPathComponent("LICENSE"))
        }
        return tree
    }

    /// The identity the starter's repository gives the wish: the same for every staging of the same starter, and no
    /// copy's own (copies keep the identity they were made with).
    static func identity(of starter: Starters.Starter) -> String {
        var bytes = Array(SHA256.hash(data: Data(("lamp-starter:" + starter.folder.lastPathComponent).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString
    }
}

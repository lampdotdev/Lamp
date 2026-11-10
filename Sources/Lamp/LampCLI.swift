import Foundation

/// Lamp's core is lamp's command line (`cli/`: JavaScript with no dependencies, which also runs with Lamp's app
/// closed). What it does, Lamp's app has it do, rather than doing the same a second time in Swift. Each call is one run
/// of `cli/calls.mjs`: the call's name is its argument, what it's given is one JSON object on its input (never in its
/// arguments, which any process on the Mac can list), and its answer is the last line it prints.
///
/// It runs as Lamp itself, as adb and Gradle's own tools do, on what Lamp hands it from Lamp's own folders. It's never
/// pointed at an app's folder: what's there is the agent's, and is read on that folder's terms (`AppFile`) or run in
/// the app's sandbox before anything of it comes here.
enum LampCLI {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// How lamp's command line is run: the program, what it's given before the call's name, and what's set for it.
    struct Launch {
        var tool: String
        var arguments: [String]
        var environment: [String: String] = [:]
    }

    /// Which copy of lamp's command line runs and on what, decided here alone; a test can put its own here.
    ///
    /// In Lamp's app it's the copy in the app (`build.sh` puts `cli/` in its Resources), on the runtime Lamp already
    /// carries: pi is built on Bun, and run with BUN_BE_BUN it is Bun itself, so Lamp ships no second runtime. Bun is
    /// told to fetch nothing and to read no .env file, both of which it would otherwise do by itself.
    /// A run from source (a test) has no app around it: the repository's copy, on the person's own Node.
    nonisolated(unsafe) static var launch: Launch? = found()

    private static func found() -> Launch? {
        let fm = FileManager.default
        if let script = Bundle.main.resourceURL?.appendingPathComponent("cli/calls.mjs"), fm.fileExists(atPath: script.path), let pi = Agent.executable {
            return Launch(tool: pi.path, arguments: ["--no-install", "--no-env-file", script.path], environment: ["BUN_BE_BUN": "1"])
        }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("cli/calls.mjs")
        guard fm.fileExists(atPath: source.path), let node = ToolLocator.path(named: "node") else { return nil }
        return Launch(tool: node, arguments: [source.path])
    }

    /// Has lamp's command line do `name` with what it's `given`, and gives back its answer. What it says the person
    /// can put right is thrown in its own words; a run that ends any other way is Lamp's own fault, and says so.
    static func call(_ name: String, _ given: [String: Any], timeout: TimeInterval = 300) async throws -> [String: Any] {
        guard let launch else { throw Failure(message: "Lamp's own tools are missing from Lamp itself.") }
        let input = try JSONSerialization.data(withJSONObject: given)
        // Run from its own folder, where nothing of the person's is: Bun reads settings from the folder it's started in.
        let home = launch.arguments.last.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        let result = await Subprocess.run(launch.tool, launch.arguments + [name], cwd: home, env: launch.environment, mergeErrors: false,
                                          timeout: timeout, input: input)
        let answer = result.output.split(separator: "\n").last
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        if let problem = answer?["problem"] as? String { throw Failure(message: problem) }
        if result.ok, let done = answer?["done"] as? [String: Any] { return done }
        let said = result.errors.split(separator: "\n").suffix(6).joined(separator: "\n")
        throw Failure(message: (result.timedOut ? "Lamp's own tools took too long." : "Lamp's own tools stopped before they answered.")
                      + (said.isEmpty ? "" : "\n\n" + said))
    }
}

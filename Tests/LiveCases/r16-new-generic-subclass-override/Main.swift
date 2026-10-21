import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    // Says so when the process dies, in place of the runtime's own message, which names addresses.
    for sig in [SIGABRT, SIGTRAP, SIGILL, SIGSEGV, SIGBUS] { signal(sig) { _ in let text = "CRASHED: the runtime refused the new subclass's method table\n"; _ = text.withCString { write(1, $0, strlen($0)) }; _exit(1) } }
    print("before:", show(Kid()), show(make()))
    reload(1)
    _ = freopen("/dev/null", "w", stderr)
    print("after1 (want kid holder: a new generic subclass's override answers, as any subclass's does):", show(Kid()), show(make()))
}}}

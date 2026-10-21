import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let kid: Any = Kid(); print("before:", describe(kid), describe(make()))
    reload(1); print("after1 (want kid:Base:kid special:Base:special, a new subclass is one of Base's):", describe(kid), describe(make()))
}}}

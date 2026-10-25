import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let player = Player(); print("before:", player.show())
    reload(1); print("after1 (want it live: a socket file's MemoryLayout<sockaddr_in> reads none of the app's structs as bytes):", player.show())
}}}

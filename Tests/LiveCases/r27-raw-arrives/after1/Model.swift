import Foundation
struct NowPlaying: Equatable { var title = "song"; var artist = "band" }
final class Player { var now = NowPlaying(); func show() -> String { "\(now.title) by \(now.artist) \(Socket.size())" } }

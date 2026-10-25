import Foundation
struct NowPlaying: Equatable { var title = "song" }
final class Player { var now = NowPlaying(); func show() -> String { now.title } }

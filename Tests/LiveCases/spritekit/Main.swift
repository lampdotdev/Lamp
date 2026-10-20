import Foundation
import SpriteKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = GameScene(size: CGSize(width: 10, height: 10))
    s.update(1); print("before:", s.log, s.score)
    reload(1)
    s.update(2); print("after (want NEW, score 102):", s.log, s.score)
    let sel = NSSelectorFromString("update:"); print("responds:", s.responds(to: sel))
}}}

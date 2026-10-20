import SpriteKit
class GameScene: SKScene {
    var log = ""; var score = 0
    override func update(_ currentTime: TimeInterval) { tick(currentTime); log += " update-NEW" }
    func tick(_ t: TimeInterval) { score += 100; log = "tick-NEW" }
}

import SpriteKit
class GameScene: SKScene {
    var log = ""; var score = 0
    override func update(_ currentTime: TimeInterval) { tick(currentTime); log += " update-old" }
    func tick(_ t: TimeInterval) { score += 1; log = "tick-old" }
}

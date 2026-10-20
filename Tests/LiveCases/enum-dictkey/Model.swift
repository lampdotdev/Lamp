import Foundation
enum Mood { case happy, sad }
final class Holder { var tally: [Mood: Int] = [.happy: 1] }

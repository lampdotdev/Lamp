import Foundation
enum Mood { case happy, sad, angry }
final class Holder { var tally: [Mood: Int] = [.happy: 1] }

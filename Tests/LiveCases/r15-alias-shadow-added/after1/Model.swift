import Foundation
struct Item { var value = 1 }
struct Special { var value = 2 }
struct Shop { var name = "shop"; typealias Item = Special }

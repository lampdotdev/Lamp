import Foundation
import Combine
final class Model: ObservableObject { var n = 1; func describe() -> String { "v1 n=\(n)" } }

import Foundation
import Combine
final class VM: ObservableObject { @Published var a = 0; func describe() -> String { "a=\(a)" } }
func poke(_ vm: VM) {}

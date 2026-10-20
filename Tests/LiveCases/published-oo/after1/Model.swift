import Foundation
import Combine
final class VM: ObservableObject { @Published var a = 0; @Published var b = 0; func describe() -> String { "a=\(a) b=\(b)" } }
func poke(_ vm: VM) { vm.b = 5 }

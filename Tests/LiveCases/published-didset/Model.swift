import Foundation
import Combine
final class VM: ObservableObject { @Published var saved = 0; func describe() -> String { "" } }
func poke(_ vm: VM) {}

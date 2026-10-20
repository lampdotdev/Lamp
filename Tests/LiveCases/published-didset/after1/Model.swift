import Foundation
import Combine
final class VM: ObservableObject {
    @Published var saved = 0
    @Published var dirty = false { didSet { saved += 1000 } }
    func describe() -> String { "dirty=\(dirty)" }
}
func poke(_ vm: VM) { vm.dirty = true }

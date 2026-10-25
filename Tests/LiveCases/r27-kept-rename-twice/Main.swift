import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let owner = Owner(); owner.panel.note = "kept"; print("before:", owner.show())
    reload(1); print("after1 (want it live: selection is computed now, note keeps its value):", owner.show())
    reload(2); print("after2 (want it live: the field kept under Lamp's name is kept again):", owner.show())
}}}

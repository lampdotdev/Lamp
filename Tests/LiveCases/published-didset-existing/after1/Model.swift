import Combine
final class Model: ObservableObject {
    @Published var a = 0 { didSet { log.append(a) } }
    @Published var b = 0
    var log: [Int] = []
}
func poke(_ m: Model) { m.a += 1; m.b = 7 }
func show(_ m: Model) -> String { "a=\(m.a) b=\(m.b) log=\(m.log)" }

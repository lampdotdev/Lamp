import Combine
final class Model: ObservableObject {
    @Published var a = 0 { didSet { log.append(a) } }
    var log: [Int] = []
}
func poke(_ m: Model) { m.a += 1 }
func show(_ m: Model) -> String { "a=\(m.a) log=\(m.log)" }

import Observation
@Observable final class N { var v = 1; func a() -> String { "A\(v)" }; func b() -> String { "b" } }
func use(_ n: N) -> String { n.a() + n.b() }

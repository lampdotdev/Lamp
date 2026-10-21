import Observation
@Observable final class N { var v = 1; func a() -> String { "a\(v)" } }
func use(_ n: N) -> String { n.a() }

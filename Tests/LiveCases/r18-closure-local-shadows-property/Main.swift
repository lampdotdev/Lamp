import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let model = Model()
    print("before:", show(model))
    reload(1); print("after1 (want price=1,234.5 in place, or a reopen; never Lamp itself crashing: a formatter added to a model, made by a closure whose local has the property's name):", show(model))
}}}

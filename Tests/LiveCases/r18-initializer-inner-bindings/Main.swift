import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let model = Model()
    print("before:", show(model))
    reload(1); print("after1 (want labels=3 like live=3, in place: a list made with a key path as a function, from an enum that grew):", show(model))
    reload(2); print("after2 (want shades=0.6/1.2, in place: a constant made by a closure with a local of its own):", show(model))
    reload(3); print("after3 (want in place, added=[]: a property added to a model, made with a key path as a function):", show(model))
}}}

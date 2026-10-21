import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    let store = Store()
    print("before:", store.summary())
    reload(1)
    print("after1 (want 1 open of 2: a method added to a model class nothing subclasses, which the copy step makes final):", store.summary())
}}}

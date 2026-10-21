import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var a = A(); var b = B(); let b2 = B()
    print("before:", show(a, b, b2))
    reload(1); bump(&a, &b); print("after1 (want aEqual=false bEqual=false bScore=9):", show(a, b, b2))
    reload(2); print("after2 (want aEqual=true bEqual=false bScore=9):", show(a, b, b2))
}}}

import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", show(s))
    reload(1); flip(s); print("after1 (want reopen; a reload's 8-byte write clobbers flag and n):", show(s))
}}}

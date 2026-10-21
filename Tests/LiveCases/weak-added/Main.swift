import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let keep = Helper(); let o = Owner(); point(o, keep); print("before:", show(o))
    reload(1); print("after1 read (want reopen; a reload reads a strong slot as weak):", show(o))
    let other = Helper(); other.name = "other"; point(o, other); print("after1 write:", show(o), "keep still", keep.name)
}}}

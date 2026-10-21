import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var note = Note(); print("before:", show(note), checksum(Data("abc".utf8)))
    reload(1); star(&note); print("after1 (want starred=true in place: no struct is read as bytes, only a Data's bytes are summed):", show(note))
}}}

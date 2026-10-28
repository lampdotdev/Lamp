import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let scene = Scene(); print("before:", scene.show())
    reload(1); print("after1 (want a reopen: Color3 is held by Vertex through an alias, and Vertex is read as bytes):", scene.show())
    reload(2); print("after2 (want a reopen: a helper now hands Packets over as bytes, and Packet gave up its spare):", scene.show())
}}}

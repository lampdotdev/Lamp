import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let scene = Scene(); print("before:", scene.show())
    reload(1); print("after1 (want it live: Label isn't read as bytes, while Vertex keeps the size it's read with):", scene.show())
    reload(2); print("after2 (want a reopen: Color3 is held by Vertex, which is read as bytes):", scene.show())
}}}

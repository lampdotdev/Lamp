import Foundation
enum Socket {
    static func size() -> Int {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        return withUnsafePointer(to: &addr) { _ in Int(MemoryLayout<sockaddr_in>.size) }
    }
}

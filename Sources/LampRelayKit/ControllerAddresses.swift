import Foundation
#if os(macOS)
import SystemConfiguration
#endif

/// Where phones reach a game's controllers, on whichever device the game runs: a Mac, an iPhone or an iPad. Read again
/// at every ask, since the device's addresses change with the network it's on. A phone is only ever given an address
/// on the device's Wi‑Fi or wired network, never a loopback one, which would point the phone at itself.
public enum ControllerAddresses {
    /// The device's IPv4 addresses on its Wi‑Fi and wired networks (the `en` interfaces on a Mac and on an iPhone or
    /// iPad), up and not loopback, the ones a phone on the same network opens: routable ones first, a self-assigned
    /// 169.254 one (a network with no router) last.
    public static func lan() -> [String] {
        var found: [String] = []
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en"), let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let text = String(cString: host)
                if !found.contains(text) { found.append(text) }
            }
        }
        return found.filter { !$0.hasPrefix("169.254.") } + found.filter { $0.hasPrefix("169.254.") }
    }

    /// The Mac's Bonjour name, as phones may reach it ("name.local"). An iPhone or iPad has no name of its own a game
    /// can read, so its phones are given an address.
    public static func localHostName() -> String? {
        #if os(macOS)
        guard let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty else { return nil }
        return name + ".local"
        #else
        return nil
        #endif
    }

    /// The names and addresses a phone page is served as: the device's on its networks, and the loopback ones.
    public static func names() -> Set<String> {
        var names: Set<String> = ["127.0.0.1", "localhost", "::1"]
        if let name = localHostName() { names.insert(name.lowercased()) }
        for address in lan() { names.insert(address.lowercased()) }
        return names
    }

    /// The host a phone's link carries: the first network address, else the Mac's Bonjour name; nil when the device is
    /// on no network a phone could share, which is said rather than handing out a link that can't work.
    public static func linkHost() -> String? { lan().first ?? localHostName() }
}

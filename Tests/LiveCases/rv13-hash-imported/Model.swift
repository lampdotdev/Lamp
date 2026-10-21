import CoreLocation
extension CLLocationCoordinate2D: @retroactive Hashable {
    public static func == (a: Self, b: Self) -> Bool { a.latitude == b.latitude && a.longitude == b.longitude }
    public func hash(into h: inout Hasher) { h.combine(latitude) }
}
enum Places {
    static var all: Set<CLLocationCoordinate2D> = []
    static func add(_ c: CLLocationCoordinate2D) { all.insert(c) }
    static func found(_ n: Int) -> Int { (0..<n).filter { all.contains(CLLocationCoordinate2D(latitude: Double($0), longitude: Double($0 * 7))) }.count }
}

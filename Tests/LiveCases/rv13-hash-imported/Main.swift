import Foundation
import CoreLocation
@main struct Main { static func main() { MainActor.assumeIsolated {
    for i in 0..<200 { Places.add(CLLocationCoordinate2D(latitude: Double(i), longitude: Double(i * 7))) }
    print("before:", Places.found(200), "of 200 found")
    reload(1); print("after1 (the app's own hash of a system type changed: want 200 found, or a reopen):", Places.found(200), "of 200 found")
}}}

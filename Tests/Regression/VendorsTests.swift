import XCTest
@testable import Lamp

/// A device's maker is read from the first digits of its hardware address, out of the list Lamp ships, and an address
/// a phone made up for itself names no maker at all.
final class VendorsTests: XCTestCase {
    private let list = Vendors.read(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/vendors.xz"))

    func testMakersComeFromTheShippedRegistryLongestPrefixFirst() throws {
        let list = try XCTUnwrap(list)
        XCTAssertGreaterThan(list.count, 30_000)
        XCTAssertEqual(Vendors.maker(of: "78:1c:3c:1f:84:bc", in: list), "Espressif")
        // The neighbor table drops leading zeros ("5c:aa:fd:5e:8:f6").
        XCTAssertEqual(Vendors.maker(of: "5c:aa:fd:5e:8:f6", in: list), "Sonos")
        // A block the registry sold on in parts names the part's buyer, not the registry.
        XCTAssertEqual(list["CCE7DE"], nil)
        XCTAssertNotNil(Vendors.maker(of: "cc:e7:de:60:09:66", in: list))
    }

    func testAMadeUpAddressIsRandomisedAndNamesNoMaker() throws {
        let list = try XCTUnwrap(list)
        XCTAssertTrue(Vendors.isRandomised("b6:b0:e2:f0:c2:40"))
        XCTAssertTrue(Vendors.isRandomised("ae:b0:a9:1:eb:44"))
        XCTAssertFalse(Vendors.isRandomised("38:b4:d3:31:25:e0"))
        XCTAssertNil(Vendors.maker(of: "b6:b0:e2:f0:c2:40", in: list))
    }
}

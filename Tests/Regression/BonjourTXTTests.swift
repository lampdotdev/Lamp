import XCTest
import dnssd
@testable import Lamp

final class BonjourTXTTests: XCTestCase {
    func testABareTXTKeyDoesNotCrashOrHideTheModel() throws {
        // DNS-SD encodes a nil value as a bare key, which crashes NetService's dictionary bridge. Build the
        // record with Apple's encoder so the check uses the wire format a service can actually publish.
        var record = TXTRecordRef()
        TXTRecordCreate(&record, 0, nil)
        defer { TXTRecordDeallocate(&record) }
        XCTAssertEqual(TXTRecordSetValue(&record, "flag", 0, nil), DNSServiceErrorType(kDNSServiceErr_NoError))
        let model = Data("Example model".utf8)
        let result = model.withUnsafeBytes {
            TXTRecordSetValue(&record, "model", UInt8($0.count), $0.baseAddress)
        }
        XCTAssertEqual(result, DNSServiceErrorType(kDNSServiceErr_NoError))
        let bytes = try XCTUnwrap(TXTRecordGetBytesPtr(&record))
        let data = Data(bytes: bytes, count: Int(TXTRecordGetLength(&record)))

        XCTAssertEqual(Bonjour.entries(ofTXTRecord: data), ["flag": Data(), "model": model])
    }
}

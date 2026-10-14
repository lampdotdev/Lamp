import XCTest
import Network
@testable import Lamp

/// The sidebar preview's page reader connects only through `PublicOnlyProxy`. An independent review showed the earlier
/// name check let a public-looking name that resolves to this Mac or the local network be opened and read; these hold
/// the line where the connection is made instead.
final class PublicOnlyProxyTests: XCTestCase {
    private func bytes(_ address: String) -> [UInt8] {
        if let v4 = IPv4Address(address) { return Array(v4.rawValue) }
        return Array(IPv6Address(address)!.rawValue)
    }

    func testAddressesThatArentTheInternetAreRefused() {
        for address in ["127.0.0.1", "127.8.9.10", "10.0.0.5", "172.16.0.1", "172.31.255.254", "192.168.1.1", "169.254.169.254",
                        "100.64.0.1", "100.127.255.255", "0.0.0.0", "224.0.0.251", "255.255.255.255", "198.18.0.1", "192.0.2.1",
                        "::", "::1", "fe80::1", "fec0::1", "fc00::1", "fd12:3456::1", "ff02::1", "::ffff:127.0.0.1", "::ffff:192.168.0.1",
                        "64:ff9b::7f00:1", "2002:7f00:1::1", "2002:c0a8:101::1", "2001:db8::1", "::127.0.0.1"] {
            XCTAssertFalse(PublicOnlyProxy.isPublic(bytes(address)), address)
        }
        for address in ["8.8.8.8", "1.1.1.1", "93.184.215.14", "100.128.0.1", "172.32.0.1", "192.169.0.1", "2606:4700:4700::1111",
                        "::ffff:8.8.8.8", "64:ff9b::808:808", "2002:808:808::1"] {
            XCTAssertTrue(PublicOnlyProxy.isPublic(bytes(address)), address)
        }
    }

    @MainActor func testANameWithATrailingDotIsStillLocalhost() {
        XCTAssertFalse(PageReader.isPublic(URL(string: "https://localhost./")!))
        XCTAssertFalse(PageReader.isPublic(URL(string: "https://router.local./")!))
    }

    /// A real proxy on this Mac: a name or address that leads here is refused before anything connects to it.
    func testTheProxyRefusesThisMacAndConnectsNowhere() async throws {
        // Something listening on this Mac, standing in for a router console or a local service.
        let service = try NWListener(using: .tcp, on: .any)
        let touched = expectation(description: "the local service was reached")
        touched.isInverted = true
        service.newConnectionHandler = { connection in touched.fulfill(); connection.cancel() }
        let serviceReady = expectation(description: "service listening")
        service.stateUpdateHandler = { if case .ready = $0 { serviceReady.fulfill() } }
        service.start(queue: .global())
        await fulfillment(of: [serviceReady], timeout: 5)
        let servicePort = service.port!.rawValue
        defer { service.cancel() }

        let proxy = try PublicOnlyProxy()
        let started = await proxy.start()
        let port = try XCTUnwrap(started)
        defer { proxy.stop() }
        for request in ["CONNECT 127.0.0.1:\(servicePort) HTTP/1.1\r\nHost: x\r\n\r\n",
                        "CONNECT localhost:\(servicePort) HTTP/1.1\r\n\r\n",
                        "CONNECT localhost.:\(servicePort) HTTP/1.1\r\n\r\n",
                        "CONNECT [::1]:\(servicePort) HTTP/1.1\r\n\r\n"] {
            let reply = try await exchange(request, port: port.rawValue)
            XCTAssertTrue(reply.hasPrefix("HTTP/1.1 403"), "\(request.prefix(40)) got \(reply.prefix(40))")
        }
        let plain = try await exchange("GET http://127.0.0.1:\(servicePort)/ HTTP/1.1\r\n\r\n", port: port.rawValue)
        XCTAssertTrue(plain.hasPrefix("HTTP/1.1 405"), plain)
        XCTAssertEqual(Set(proxy.refused), ["127.0.0.1", "localhost", "localhost.", "::1"])
        await fulfillment(of: [touched], timeout: 1)
    }

    private func exchange(_ request: String, port: UInt16) async throws -> String {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        defer { connection.cancel() }
        connection.start(queue: .global())
        connection.send(content: Data(request.utf8), completion: .idempotent)
        return try await withCheckedThrowingContinuation { done in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                if let error { done.resume(throwing: error) } else { done.resume(returning: String(decoding: data ?? Data(), as: UTF8.self)) }
            }
        }
    }
}

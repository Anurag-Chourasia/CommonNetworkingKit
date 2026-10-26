import Foundation
import XCTest
@testable import CommonNetworkingKit

private final class Records: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}
private final class LoggingProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url!.path == "/offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json", "Set-Cookie": "secret-cookie"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"success":false,"token":"secret-token","message":"try again"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class HTTPLoggerTests: XCTestCase {
    func testNestedJSONHeadersURLAndAdditionalKeysAreRedactedWithoutChangingRequest() throws {
        let records = Records()
        let logger = HTTPLogger(additionalSensitiveKeys: ["accountNumber"], output: records.append)
        var request = URLRequest(url: URL(string: "https://user:pass@example.com/login?email=secret-mail&safe=ok#secret-fragment")!)
        request.httpMethod = "POST"
        request.setValue("Bearer secret-auth", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"email":"secret-email","nested":[{"PASSWORD":"secret-password","access_token":"secret-token","account_number":"secret-account"}],"safe":"visible"}"#.utf8)
        let original = request
        logger.request(request, id: "id")
        let log = try XCTUnwrap(records.values.first)
        for secret in ["secret-mail", "secret-fragment", "secret-auth", "secret-email", "secret-password", "secret-token", "secret-account", "user:pass"] {
            XCTAssertFalse(log.contains(secret), secret)
        }
        XCTAssertTrue(log.contains("<REDACTED>"))
        XCTAssertTrue(log.contains("visible"))
        XCTAssertTrue(log.contains("Content-Type: application/json"))
        XCTAssertEqual(request, original)
    }

    func testMultiMegabyteBodyAndUnicodeSurviveConsoleChunking() throws {
        let records = Records()
        let logger = HTTPLogger(output: records.append)
        let payload = String(repeating: "abc🔒हिंदी\n", count: 200_000) + "END-OF-BODY"
        let data = try JSONSerialization.data(withJSONObject: ["payload": payload])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        logger.response(response, data: data, request: request, id: "big", milliseconds: 342)
        let record = try XCTUnwrap(records.values.first)
        let body = try XCTUnwrap(record.components(separatedBy: "Response Body:\n").last?.components(separatedBy: "\n==================================").first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: String])
        XCTAssertEqual(json["payload"], payload)
        var chunks: [String] = []
        HTTPLogger.writeChunks(record) { chunks.append($0) }
        XCTAssertGreaterThan(chunks.count, 1000)
        XCTAssertEqual(chunks.joined(), record)
        XCTAssertTrue(record.contains("Duration: 342.00 ms"))
    }

    func testFormEmptyBinaryAndStreamBodies() throws {
        let records = Records()
        let logger = HTTPLogger(output: records.append)
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("%65mail=hidden&password=hidden2&name=Hello+World&bad=%ZZ&".utf8)
        logger.request(request, id: "form")
        XCTAssertFalse(records.values[0].contains("hidden"))
        XCTAssertTrue(records.values[0].contains("Hello World"))
        request.httpBody = nil
        logger.request(request, id: "empty")
        XCTAssertTrue(records.values[1].contains("<empty>"))
        request.setValue(nil, forHTTPHeaderField: "Content-Type")
        request.httpBody = Data([0xff, 0xfe, 0x00, 0x80])
        logger.request(request, id: "binary")
        XCTAssertTrue(records.values[2].contains("//4AgA=="))
        request.httpBody = nil
        let stream = InputStream(data: Data("do not read".utf8))
        request.httpBodyStream = stream
        logger.request(request, id: "stream")
        XCTAssertEqual(stream.streamStatus, .notOpen)
        XCTAssertTrue(records.values[3].contains("stream body unavailable"))
    }

    func testConcurrentRequestsHaveUniquePairedIDsAndNon2xxBodies() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LoggingProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let records = Records()
        let client = HTTPClient(session: session, logger: HTTPLogger(output: records.append))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    let result = try await client.send(URLRequest(url: URL(string: "https://example.com/\(index)")!))
                    XCTAssertEqual(result.statusCode, 503)
                    XCTAssertTrue(String(decoding: result.data, as: UTF8.self).contains("secret-token"))
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(records.values.count, 24)
        let pairs = Dictionary(grouping: records.values) { record in
            record.components(separatedBy: "\n").first { $0.hasPrefix("Request ID:") }!
        }
        XCTAssertEqual(pairs.count, 12)
        for pair in pairs.values {
            XCTAssertEqual(pair.count, 2)
            XCTAssertTrue(pair[0].contains("HTTP REQUEST"))
            XCTAssertTrue(pair[1].contains("HTTP RESPONSE"))
            XCTAssertTrue(pair[1].contains("Status: 503"))
            XCTAssertFalse(pair[1].contains("secret-cookie"))
            XCTAssertFalse(pair[1].contains("secret-token"))
        }
    }

    func testTransportFailureUsesRequestIDAndPreservesError() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LoggingProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let records = Records()
        let client = HTTPClient(session: session, logger: HTTPLogger(output: records.append))
        do {
            _ = try await client.send(URLRequest(url: URL(string: "https://example.com/offline?token=hidden")!))
            XCTFail("Expected failure")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(records.values.count, 2)
        XCTAssertTrue(records.values[1].contains("HTTP ERROR"))
        XCTAssertFalse(records.values.joined().contains("hidden"))
        XCTAssertEqual(records.values[0].components(separatedBy: "\n")[1], records.values[1].components(separatedBy: "\n")[1])
    }
}

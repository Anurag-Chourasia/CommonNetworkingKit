import Foundation
import XCTest
import CommonNetworkingKit

// Every request is intercepted, including unknown routes. No shared mutable fixture state.
private final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let path = url.path
        if path == "/hold" {
            (Self.property(forKey: "started", in: request) as? XCTestExpectation)?.fulfill()
            return
        }
        if path == "/cancelled" || path == "/offline" {
            client?.urlProtocol(self, didFailWithError: URLError(
                path == "/cancelled" ? .cancelled : .notConnectedToInternet,
                userInfo: ["fixture": "preserved"]))
            return
        }
        let response: URLResponse
        let body: Data
        if path == "/non-http" {
            response = URLResponse(url: url, mimeType: "application/json",
                                   expectedContentLength: 2, textEncodingName: nil)
            body = Data("{}".utf8)
        } else if let status = Int(path.dropFirst()),
                  let httpResponse = HTTPURLResponse(url: url, statusCode: status,
                                                     httpVersion: "HTTP/1.1", headerFields: ["X-Fixture": "retained"]) {
            response = httpResponse
            switch request.value(forHTTPHeaderField: "X-Body") {
            case "empty": body = Data()
            case "invalid": body = Data("not-json".utf8)
            case "whitespace": body = Data(" \n".utf8)
            case "echo":
                body = Data("\(request.httpMethod ?? "")|\(request.value(forHTTPHeaderField: "X-Caller") ?? "")".utf8)
            default: body = Data(#"{"display_name":"fixture"}"#.utf8)
            }
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        (Self.property(forKey: "stopped", in: request) as? XCTestExpectation)?.fulfill()
    }
}

final class HTTPClientTests: XCTestCase {
    private struct Model: Decodable {
        let display_name: String
    }
    private struct CamelModel: Decodable { let displayName: String }
    // Deliberately mutable and non-Sendable: generic decoding must not exclude it.
    private final class MutableModel: Decodable { var display_name: String }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }
    private func request(_ path: String, body: String? = nil) -> URLRequest {
        guard let url = URL(string: "https://fixture.invalid/\(path)") else {
            fatalError("Invalid fixture URL for path: \(path)")
        }
        var request = URLRequest(url: url)
        request.setValue(body, forHTTPHeaderField: "X-Body")
        return request
    }

    func testRawRetainsStatusBodyAndMetadata() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let client = HTTPClient(session: session)
        for status in [200, 201, 204, 299, 300, 400, 404, 500] {
            let input = request("\(status)")
            let result = try await client.send(input)
            XCTAssertEqual(result.statusCode, status)
            XCTAssertEqual(result.response.url, input.url)
            XCTAssertEqual(result.response.value(forHTTPHeaderField: "X-Fixture"), "retained")
            XCTAssertEqual(result.data, Data(#"{"display_name":"fixture"}"#.utf8))
        }
    }

    func testCallerRequestMethodAndHeadersSurvive() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        var input = request("200", body: "echo")
        input.httpMethod = "POST"
        input.setValue("custom", forHTTPHeaderField: "X-Caller")
        let result = try await HTTPClient(session: session).send(input)
        XCTAssertEqual(String(decoding: result.data, as: UTF8.self), "POST|custom")
    }

    func testTypedAcceptsEntireSuccessRangeAndMutableModel() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let client = HTTPClient(session: session)
        for status in [200, 201, 299] {
            let result = try await client.request(request("\(status)"), as: Model.self)
            XCTAssertEqual(result.display_name, "fixture")
        }
        let mutable = try await client.request(request("200"), as: MutableModel.self)
        mutable.display_name = "changed"
        XCTAssertEqual(mutable.display_name, "changed")
    }

    func testInjectedDecoderAndFreshDefaultDecoder() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let client = HTTPClient(session: session)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try await client.request(request("200"), as: CamelModel.self, decoder: decoder)
        XCTAssertEqual(result.displayName, "fixture")
        do {
            let _ = try await client.request(request("200"), as: CamelModel.self)
            XCTFail("Default decoder must not inherit injected configuration")
        } catch is DecodingError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testTypedStatusErrorsRetainCompleteResponseBeforeBodyValidation() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let client = HTTPClient(session: session)
        for status in [199, 300, 401, 500] {
            for body in ["empty", "invalid"] {
                let input = request("\(status)", body: body)
                do {
                    let _ = try await client.request(input, as: Model.self)
                    XCTFail("Expected status error")
                } catch HTTPClientError.unsuccessfulStatus(let result) {
                    XCTAssertEqual(result.statusCode, status)
                    XCTAssertEqual(result.response.url, input.url)
                    XCTAssertEqual(result.response.value(forHTTPHeaderField: "X-Fixture"), "retained")
                    XCTAssertEqual(result.data, body == "empty" ? Data() : Data("not-json".utf8))
                } catch { XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testEmptyRawSucceedsButTypedRejectsEmptySuccess() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let client = HTTPClient(session: session)
        for status in [200, 204] {
            let input = request("\(status)", body: "empty")
            let raw = try await client.send(input)
            XCTAssertTrue(raw.data.isEmpty)
            do {
                let _ = try await client.request(input, as: Model.self)
                XCTFail("Expected empty body error")
            } catch HTTPClientError.emptyBody(let result) {
                XCTAssertEqual(result.statusCode, status)
                XCTAssertTrue(result.data.isEmpty)
            } catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testInvalidAndWhitespaceJSONPreserveDecodingError() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        for body in ["invalid", "whitespace"] {
            do {
                let _ = try await HTTPClient(session: session).request(request("200", body: body), as: Model.self)
                XCTFail("Expected decoding error")
            } catch is DecodingError {} catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testNonHTTPResponseRejectedByBothPaths() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let client = HTTPClient(session: session)
        do {
            _ = try await client.send(request("non-http"))
            XCTFail("Expected non-HTTP error")
        } catch HTTPClientError.nonHTTPResponse {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            let _ = try await client.request(request("non-http"), as: Model.self)
            XCTFail("Expected non-HTTP error")
        } catch HTTPClientError.nonHTTPResponse {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testUnrelatedTransportErrorPreserved() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let client = HTTPClient(session: session)
        for typed in [false, true] {
            do {
                if typed {
                    _ = try await client.request(request("offline"), as: Model.self)
                } else {
                    _ = try await client.send(request("offline"))
                }
                XCTFail("Expected offline error")
            } catch let error as URLError {
                XCTAssertEqual(error.code, .notConnectedToInternet)
                XCTAssertEqual(error.userInfo["fixture"] as? String, "preserved")
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCancelledTransportNormalizedOnBothPaths() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let client = HTTPClient(session: session)
        for typed in [false, true] {
            do {
                if typed {
                    _ = try await client.request(request("cancelled"), as: Model.self)
                } else {
                    _ = try await client.send(request("cancelled"))
                }
                XCTFail("Expected cancellation")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCancellingInFlightTaskStopsLoading() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let client = HTTPClient(session: session)
        let started = expectation(description: "started")
        let stopped = expectation(description: "stopped")
        guard let url = URL(string: "https://fixture.invalid/hold") else {
            fatalError("Invalid fixture URL")
        }
        let input = NSMutableURLRequest(url: url)
        URLProtocol.setProperty(started, forKey: "started", in: input)
        URLProtocol.setProperty(stopped, forKey: "stopped", in: input)
        let value = input as URLRequest
        let task = Task { try await client.send(value) }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await fulfillment(of: [stopped], timeout: 5)
    }
}

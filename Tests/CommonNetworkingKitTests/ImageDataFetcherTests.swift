import Foundation
import XCTest
import CommonNetworkingKit

private final class ImageStubProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        if url.path == "/delayed" {
            Thread.sleep(forTimeInterval: 0.08)
            guard let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data([0xDE, 0xAD, 0xBE, 0xEF]))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if url.path == "/empty" {
            guard let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if url.path == "/error" {
            guard let http = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("not found".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        guard let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([0x89, 0x50, 0x4E, 0x47]))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ImageDataFetcherTests: XCTestCase {
    private var session: URLSession?

    override func setUp() {
        super.setUp()
        ImageStubProtocol.requestCount = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageStubProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        session = nil
        super.tearDown()
    }

    func testFetchDataSucceedsWithValidData() async throws {
        guard let session else { return XCTFail("Missing session") }
        let fetcher = ImageDataFetcher(session: session)
        guard let url = URL(string: "https://example.com/image.png") else { return XCTFail("Invalid URL") }

        let data = try await fetcher.fetchData(for: url)

        XCTAssertEqual(data, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(ImageStubProtocol.requestCount, 1)
    }

    func testFetchDataThrowsForUnsuccessfulStatus() async {
        guard let session else { return XCTFail("Missing session") }
        let fetcher = ImageDataFetcher(session: session)
        guard let url = URL(string: "https://example.com/error") else { return XCTFail("Invalid URL") }

        do {
            _ = try await fetcher.fetchData(for: url)
            XCTFail("Expected unsuccessfulStatus error")
        } catch let HTTPClientError.unsuccessfulStatus(response) {
            XCTAssertEqual(response.statusCode, 404)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchDataThrowsForEmptyBody() async {
        guard let session else { return XCTFail("Missing session") }
        let fetcher = ImageDataFetcher(session: session)
        guard let url = URL(string: "https://example.com/empty") else { return XCTFail("Invalid URL") }

        do {
            _ = try await fetcher.fetchData(for: url)
            XCTFail("Expected emptyBody error")
        } catch HTTPClientError.emptyBody {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchDataDeduplicatesConcurrentRequests() async throws {
        guard let session else { return XCTFail("Missing session") }
        let fetcher = ImageDataFetcher(session: session)
        guard let url = URL(string: "https://example.com/delayed") else { return XCTFail("Invalid URL") }

        async let fetch1 = fetcher.fetchData(for: url)
        async let fetch2 = fetcher.fetchData(for: url)
        async let fetch3 = fetcher.fetchData(for: url)

        let (data1, data2, data3) = try await (fetch1, fetch2, fetch3)

        XCTAssertEqual(data1, Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertEqual(data2, data1)
        XCTAssertEqual(data3, data1)
        XCTAssertEqual(ImageStubProtocol.requestCount, 1)
        let inFlight = await fetcher.inFlightCount()
        XCTAssertEqual(inFlight, 0)
    }

    func testFetchDataFromFileURL() async throws {
        guard let session else { return XCTFail("Missing session") }
        let fetcher = ImageDataFetcher(session: session)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dat")
        let sampleData = Data([0x01, 0x02, 0x03, 0x04])
        try sampleData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fetchedData = try await fetcher.fetchData(for: tempURL)

        XCTAssertEqual(fetchedData, sampleData)
    }

    func testFetchDataHonorsCancellation() async {
        guard let session else { return XCTFail("Missing session") }
        let fetcher = ImageDataFetcher(session: session)
        guard let url = URL(string: "https://example.com/delayed") else { return XCTFail("Invalid URL") }

        let task = Task {
            try await fetcher.fetchData(for: url)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected
        } catch {
            // Cancelled
        }
    }

    func testFetchDataWithDefaultClientAndCache() async {
        let fetcher = ImageDataFetcher()
        guard let url = URL(string: "https://example.com/invalid_host_unreachable_\(UUID().uuidString)") else { return XCTFail("Invalid URL") }
        do {
            _ = try await fetcher.fetchData(for: url)
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testFetchDataFromFileURLThrowsForEmptyData() async throws {
        let fetcher = ImageDataFetcher()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dat")
        try Data().write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await fetcher.fetchData(for: tempURL)
            XCTFail("Expected emptyBody error")
        } catch HTTPClientError.emptyBody {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

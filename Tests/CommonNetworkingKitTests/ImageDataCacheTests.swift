import Foundation
import XCTest
import CommonNetworkingKit

private final class CacheStubProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        guard let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([0xCA, 0xFE, 0xBA, 0xBE]))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ImageDataCacheTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        CacheStubProtocol.requestCount = 0
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ImageCacheTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    func testCacheStoresAndRetrievesData() async {
        let cache = PersistentImageDataCache(diskDirectory: tempDirectory)
        guard let url = URL(string: "https://example.com/item.png") else { return XCTFail("Invalid URL") }
        let sampleData = Data([0x01, 0x02, 0x03, 0x04])

        await cache.store(sampleData, for: url)
        let retrieved = await cache.data(for: url)

        XCTAssertEqual(retrieved, sampleData)
    }

    func testCachePersistsToDiskAndSurvivesNewInstance() async {
        guard let url = URL(string: "https://example.com/disk.png") else { return XCTFail("Invalid URL") }
        let sampleData = Data([0xAA, 0xBB, 0xCC, 0xDD])

        let cache1 = PersistentImageDataCache(diskDirectory: tempDirectory)
        await cache1.store(sampleData, for: url)

        // New cache instance pointing to same disk directory (empty memory cache)
        let cache2 = PersistentImageDataCache(diskDirectory: tempDirectory)
        let retrieved = await cache2.data(for: url)

        XCTAssertEqual(retrieved, sampleData)
    }

    func testCacheRemoveData() async {
        let cache = PersistentImageDataCache(diskDirectory: tempDirectory)
        guard let url = URL(string: "https://example.com/remove.png") else { return XCTFail("Invalid URL") }
        let sampleData = Data([0x11, 0x22])

        await cache.store(sampleData, for: url)
        await cache.removeData(for: url)
        let retrieved = await cache.data(for: url)

        XCTAssertNil(retrieved)
    }

    func testCacheClearRemovesAll() async {
        let cache = PersistentImageDataCache(diskDirectory: tempDirectory)
        guard let url1 = URL(string: "https://example.com/1.png"),
              let url2 = URL(string: "https://example.com/2.png") else { return XCTFail("Invalid URLs") }

        await cache.store(Data([0x01]), for: url1)
        await cache.store(Data([0x02]), for: url2)
        await cache.clear()

        let retrieved1 = await cache.data(for: url1)
        let retrieved2 = await cache.data(for: url2)

        XCTAssertNil(retrieved1)
        XCTAssertNil(retrieved2)
    }

    func testImageDataFetcherReturnsCachedDataWithoutNetworkRequest() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CacheStubProtocol.self]
        let session = URLSession(configuration: config)

        let cache = PersistentImageDataCache(diskDirectory: tempDirectory)
        guard let url = URL(string: "https://example.com/preloaded.png") else { return XCTFail("Invalid URL") }
        let cachedData = Data([0x99, 0x88, 0x77])
        await cache.store(cachedData, for: url)

        let fetcher = ImageDataFetcher(session: session, cache: cache)
        let data = try await fetcher.fetchData(for: url)

        XCTAssertEqual(data, cachedData)
        XCTAssertEqual(CacheStubProtocol.requestCount, 0)
    }

    func testImageDataFetcherPopulatesCacheOnFetch() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CacheStubProtocol.self]
        let session = URLSession(configuration: config)

        let cache = PersistentImageDataCache(diskDirectory: tempDirectory)
        guard let url = URL(string: "https://example.com/new.png") else { return XCTFail("Invalid URL") }

        let fetcher = ImageDataFetcher(session: session, cache: cache)
        let data = try await fetcher.fetchData(for: url)

        XCTAssertEqual(data, Data([0xCA, 0xFE, 0xBA, 0xBE]))
        XCTAssertEqual(CacheStubProtocol.requestCount, 1)

        // Second fetch should hit the populated cache
        let cachedData = try await fetcher.fetchData(for: url)
        XCTAssertEqual(cachedData, data)
        XCTAssertEqual(CacheStubProtocol.requestCount, 1)
    }
}

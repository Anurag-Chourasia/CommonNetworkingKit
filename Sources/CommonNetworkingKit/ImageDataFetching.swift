import Foundation

/// A domain-agnostic protocol for fetching raw image data over HTTP or local file URLs.
/// Operates strictly on `Data` to guarantee zero UI dependencies (no UIKit/AppKit/SwiftUI).
public protocol ImageDataFetching: Sendable {
    func fetchData(for url: URL) async throws -> Data
}

/// An actor that coordinates image data fetches, checks cache, and deduplicates in-flight requests for identical URLs.
public actor ImageDataFetcher: ImageDataFetching {
    private let client: HTTPClient
    private let cache: (any ImageDataCaching)?
    private var inFlightTasks: [URL: Task<Data, Error>] = [:]

    public init(
        client: HTTPClient = HTTPClient(),
        cache: (any ImageDataCaching)? = nil
    ) {
        self.client = client
        self.cache = cache
    }

    public init(
        session: URLSession,
        cache: (any ImageDataCaching)? = nil
    ) {
        self.client = HTTPClient(session: session)
        self.cache = cache
    }

    /// Fetches data for the given URL, checking cache first and deduplicating concurrent in-flight requests.
    public func fetchData(for url: URL) async throws -> Data {
        try Task.checkCancellation()

        if url.isFileURL {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) ?? HTTPURLResponse()
                throw HTTPClientError.emptyBody(HTTPResponse(data: data, response: response))
            }
            return data
        }

        if let cached = await cache?.data(for: url) {
            return cached
        }

        if let existingTask = inFlightTasks[url] {
            return try await existingTask.value
        }

        let task = Task<Data, Error> { [client, cache] in
            let request = URLRequest(url: url)
            let response = try await client.send(request)
            guard (200..<300).contains(response.statusCode) else {
                throw HTTPClientError.unsuccessfulStatus(response)
            }
            guard !response.data.isEmpty else {
                throw HTTPClientError.emptyBody(response)
            }
            await cache?.store(response.data, for: url)
            return response.data
        }

        inFlightTasks[url] = task

        do {
            let data = try await task.value
            inFlightTasks[url] = nil
            return data
        } catch {
            inFlightTasks[url] = nil
            throw error
        }
    }

    /// Returns the number of currently active in-flight fetch tasks.
    public func inFlightCount() -> Int {
        inFlightTasks.count
    }
}

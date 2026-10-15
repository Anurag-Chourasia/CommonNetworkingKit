import Foundation

/// An HTTP exchange, including bytes and metadata for any HTTP status code.
public struct HTTPResponse: Sendable {
    public let data: Data
    public let response: HTTPURLResponse
    public var statusCode: Int { response.statusCode }

    public init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }
}

/// Errors introduced by HTTP validation. Transport and decoding errors remain unwrapped.
public enum HTTPClientError: Error {
    /// URLSession returned a response that is not HTTP.
    case nonHTTPResponse
    /// Typed decoding requires 200..<300. The complete response is retained.
    case unsuccessfulStatus(HTTPResponse)
    /// A successful HTTP response had zero bytes; there is no JSON value to decode.
    case emptyBody(HTTPResponse)
}

/// Foundation transport with optional JSON decoding. Owns neither endpoints nor app policy.
public struct HTTPClient: Sendable {
    private let session: URLSession
    private let logger: HTTPLogger?

    /// The caller owns session configuration and lifetime.
    public init(session: URLSession = .shared, logger: HTTPLogger? = nil) {
        self.session = session
        self.logger = logger
    }

    /// Returns bytes and metadata for every HTTP status, including non-2xx and empty bodies.
    /// Converts URLError.cancelled to CancellationError; other transport errors are unchanged.
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let id = logger == nil ? "" : UUID().uuidString
        logger?.request(request, id: id)
        let start = DispatchTime.now().uptimeNanoseconds
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger?.failure(error, request: request, id: id, milliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            if let error = error as? URLError, error.code == .cancelled { throw CancellationError() }
            throw error
        }
        logger?.response(response, data: data, request: request, id: id, milliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        guard let response = response as? HTTPURLResponse else {
            throw HTTPClientError.nonHTTPResponse
        }
        return HTTPResponse(data: data, response: response)
    }

    /// Validates status, rejects empty bodies, then decodes with the caller's decoder.
    /// The default expression creates a fresh decoder per call. Do not concurrently mutate
    /// an injected decoder. For actor-isolated Decodable conformances, use send and decode
    /// its data on the owning actor instead. No Sendable conformance is required of T.
    public func request<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let result = try await send(request)
        guard (200..<300).contains(result.statusCode) else {
            throw HTTPClientError.unsuccessfulStatus(result)
        }
        guard !result.data.isEmpty else {
            throw HTTPClientError.emptyBody(result)
        }
        return try decoder.decode(type, from: result.data)
    }
}

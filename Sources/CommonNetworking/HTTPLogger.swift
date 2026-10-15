import Foundation

/// Opt-in diagnostics. Receives complete, redacted records with no body-size limit.
/// Custom sinks must be thread-safe; requests may finish concurrently.
public struct HTTPLogger: Sendable {
    private let output: @Sendable (String) -> Void
    private let sensitiveKeys: Set<String>

    /// Additional keys extend (never remove) the default redaction policy.
    public init(
        additionalSensitiveKeys: Set<String> = [],
        output: @escaping @Sendable (String) -> Void
    ) {
        self.output = output
        self.sensitiveKeys = Set((Self.defaults.union(additionalSensitiveKeys)).map(Self.normalized))
    }

    /// Serializes complete records and writes bounded chunks to standard output.
    /// Console retention limits are controlled by the host, not this package.
    public static var console: HTTPLogger {
        HTTPLogger { record in
            consoleLock.lock()
            defer { consoleLock.unlock() }
            writeChunks(record) { Swift.print($0, terminator: "") }
        }
    }

    private static let consoleLock = NSLock()
    private static let defaults: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key", "api-key",
        "apiKey", "password", "passwd", "pwd", "email", "token", "access_token", "refresh_token",
        "id_token", "client_secret", "secret", "credential", "credentials", "session", "sessionId"
    ]
    private static func normalized(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }
    private func sensitive(_ key: String) -> Bool { sensitiveKeys.contains(Self.normalized(key)) }

    // Internal so the console's exact chunking path can be tested without redirecting stdout.
    static func writeChunks(_ record: String, write: (String) -> Void) {
        var start = record.startIndex
        while start < record.endIndex {
            let end = record.index(start, offsetBy: 1024, limitedBy: record.endIndex) ?? record.endIndex
            write(String(record[start..<end]))
            start = end
        }
    }

    func request(_ request: URLRequest, id: String) {
        output("""
        ========== HTTP REQUEST ==========
        Request ID: \(id)
        Method: \(request.httpMethod ?? "GET")
        URL: \(url(request.url))
        Headers:
        \(headers(request.allHTTPHeaderFields ?? [:]))
        Request Body:
        \(request.httpBodyStream != nil ? "<stream body unavailable; stream is not consumed by logging>" : body(request.httpBody, contentType: request.value(forHTTPHeaderField: "Content-Type")))
        =================================

        """)
    }

    func response(_ response: URLResponse, data: Data, request: URLRequest, id: String, milliseconds: Double) {
        let http = response as? HTTPURLResponse
        let fields = http?.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key)] = String(describing: pair.value)
        } ?? [:]
        output("""
        ========== HTTP RESPONSE =========
        Request ID: \(id)
        Method: \(request.httpMethod ?? "GET")
        URL: \(url(request.url))
        Final URL: \(url(response.url))
        Status: \(http.map { String($0.statusCode) } ?? "<non-HTTP response>")
        Duration: \(String(format: "%.2f", milliseconds)) ms
        Headers:
        \(headers(fields))
        Response Body:
        \(body(data, contentType: http?.value(forHTTPHeaderField: "Content-Type")))
        ==================================

        """)
    }

    func failure(_ error: Error, request: URLRequest, id: String, milliseconds: Double) {
        // localizedDescription/userInfo can embed an unredacted URL or credentials.
        let reason = (error as? URLError).map { "URLError (\($0.code.rawValue))" }
            ?? (error is CancellationError ? "CancellationError" : "Transport error")
        output("""
        ========== HTTP ERROR ============
        Request ID: \(id)
        Method: \(request.httpMethod ?? "GET")
        URL: \(url(request.url))
        Duration: \(String(format: "%.2f", milliseconds)) ms
        Error: \(reason)
        ==================================

        """)
    }

    private func url(_ url: URL?) -> String {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "<no URL>" }
        if parts.user != nil { parts.user = "<REDACTED>" }
        if parts.password != nil { parts.password = "<REDACTED>" }
        if let query = parts.queryItems {
            parts.queryItems = query.map { URLQueryItem(name: $0.name, value: sensitive($0.name) ? "<REDACTED>" : $0.value) }
        }
        // Fragments are not sent over HTTP and may contain OAuth credentials.
        if parts.fragment != nil { parts.fragment = "<REDACTED>" }
        return parts.string ?? "<invalid URL>"
    }

    private func headers(_ fields: [String: String]) -> String {
        if fields.isEmpty { return "  <none>" }
        return fields.sorted { $0.key < $1.key }.map { key, value in
            "  \(key): \(sensitive(key) ? "<REDACTED>" : value)"
        }.joined(separator: "\n")
    }

    private func redact(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValuesWithKeys { key, value in sensitive(key) ? "<REDACTED>" : redact(value) }
        }
        if let array = value as? [Any] { return array.map(redact) }
        return value
    }

    private func body(_ data: Data?, contentType: String?) -> String {
        guard let data, !data.isEmpty else { return "<empty>" }
        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let formatted = try? JSONSerialization.data(withJSONObject: redact(json), options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
           let text = String(data: formatted, encoding: .utf8) { return text }
        if contentType?.lowercased().contains("application/x-www-form-urlencoded") == true,
           let text = String(data: data, encoding: .utf8) {
            return text.split(separator: "&", omittingEmptySubsequences: false).map { pair in
                let fields = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                func decode(_ field: Substring) -> String {
                    let value = field.replacingOccurrences(of: "+", with: " ")
                    return value.removingPercentEncoding ?? value
                }
                let key = decode(fields[0])
                let value = fields.count > 1 ? decode(fields[1]) : ""
                return "\(key): \(sensitive(key) ? "<REDACTED>" : value)"
            }.joined(separator: "\n")
        }
        // Unstructured text/binary has no reliable field boundaries for key-based redaction.
        if let text = String(data: data, encoding: .utf8) { return text }
        return "<base64; \(data.count) bytes>\n" + data.base64EncodedString()
    }
}

private extension Dictionary where Key == String, Value == Any {
    func mapValuesWithKeys(_ transform: (String, Any) -> Any) -> [String: Any] {
        reduce(into: [:]) { result, pair in result[pair.key] = transform(pair.key, pair.value) }
    }
}

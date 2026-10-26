# CommonNetworkingKit

A small Foundation-only Swift package for HTTP transport and optional JSON decoding. Extracted and adapted from [Anurag Chourasia's MyTV app](https://github.com/Anurag-Chourasia/myTV).

**iOS 16.6+ · Manifest tools 5.9 · Validated with Xcode 27.0 / Swift 6.4 · MIT**

MyTV and ShowBook consume this package through app-owned adapters.

## Install

In Xcode, choose **File → Add Package Dependencies** and enter:

```text
https://github.com/Anurag-Chourasia/CommonNetworkingKit.git
```

Select **Exact Version: 1.1.0** to reproduce this release, then add the `CommonNetworkingKit` library product to your app target. Commit the app's `Package.resolved` file. For a consuming Swift package:

```swift
// In Package.swift:
.package(url: "https://github.com/Anurag-Chourasia/CommonNetworkingKit.git", exact: "1.1.0")
// In the consuming target's dependencies:
.product(name: "CommonNetworkingKit", package: "CommonNetworkingKit")
```

> [!NOTE]
> For backward compatibility, the `CommonNetworking` library product and module name are preserved as an alias.

This is source distributed through Swift Package Manager, not a prebuilt binary XCFramework. No registry account or CocoaPods installation is needed. The library declares iOS 16.6 as its deployment floor. Host tests run on macOS as a validation technique; this is not a declaration of macOS platform support.

## Quick start

Build the request in the app that owns the endpoint and model. The package deliberately does not define application endpoints, DTOs, API envelopes, authentication, retries, or app-specific error mappings.

```swift
import CommonNetworkingKit
import Foundation

struct Profile: Decodable {
    let id: Int
    let name: String
}

func loadProfile(id: Int) async throws -> Profile {
    let client = HTTPClient()
    let request = URLRequest(url: URL(string: "https://example.com/profiles/\(id)")!)
    return try await client.request(request, as: Profile.self)
}
```

Inject a configured `URLSession` when the host app needs specific session behavior or deterministic tests:

```swift
let session = URLSession(configuration: .ephemeral)
let client = HTTPClient(session: session)
```

The default JSONDecoder is created per typed call. Do not concurrently mutate an injected decoder.

The caller owns session configuration and lifetime. `CommonNetworking` does not invalidate injected sessions.

## Public API and behaviour

| API | Behaviour |
| --- | --- |
| `HTTPClient(session:logger:)` | Concrete transport using the supplied session; defaults to `URLSession.shared`. |
| `send(_:)` | Executes the supplied `URLRequest` and returns response bytes plus HTTP metadata for every HTTP status, including non-2xx and empty bodies. |
| `request(_:as:decoder:)` | Accepts only 2xx statuses, rejects a zero-byte successful body, then decodes JSON. The decoder is caller-configurable. |
| `HTTPResponse` | Retains `Data` and the full `HTTPURLResponse`, including status, headers and final URL. |
| `HTTPClientError` | Distinguishes non-HTTP responses, unsuccessful statuses, and empty bodies for typed decoding. Status/body errors retain the complete HTTP response. |

`send` does not reject an HTTP 4xx or 5xx response; the caller chooses how to interpret the status and body. `request` performs status validation before empty-body validation and decoding. A malformed 500 therefore produces an unsuccessful-status error rather than a decoding error. A 204 or any other empty successful response can be consumed through `send`; typed decoding reports `emptyBody`.

JSON decoding errors and unrelated transport errors propagate without generic wrapping. A transport `URLError.cancelled` becomes `CancellationError`; other `URLError` values are preserved. URLSession redirect, cookie, cache and other session behaviors remain under the injected session's configuration. There are no automatic retries, authentication handlers or caching rules. Logging is opt-in and does not change transport or decoding behavior.

## Raw response handling

For endpoints that return non-JSON data, or where the application needs to apply its own status policy, consume the raw response:

```swift
let response = try await client.send(request)
if (200..<300).contains(response.statusCode) {
    let bytes = response.data
    // Pass bytes to the app-owned parser.
} else {
    // Interpret status and response.data according to the app's API contract.
}
```

## Actor-owned decoding

The generic API intentionally does **not** impose `T: Sendable`. If a model's `Decodable` conformance is explicitly actor-isolated, use the raw path and decode on its owning actor after applying the required status/body policy:

```swift
@MainActor
func loadActorModel(_ request: URLRequest, using client: HTTPClient) async throws -> ActorModel {
    let response = try await client.send(request)
    guard (200..<300).contains(response.statusCode) else {
        throw HTTPClientError.unsuccessfulStatus(response)
    }
    guard !response.data.isEmpty else {
        throw HTTPClientError.emptyBody(response)
    }
    return try JSONDecoder().decode(ActorModel.self, from: response.data)
}
```

Decoding above runs synchronously on the owning actor. Large payloads can affect UI responsiveness; measure workload before choosing a main-actor decoding path. The library adds no unchecked `Sendable` conformances, blanket actor annotations, or DTO annotations.

## Validation and toolchain

The package's validated baseline is Xcode 27.0 / Swift 6.4. The manifest's `swift-tools-version: 5.9` selects manifest and package-tool semantics; it does not guarantee compatibility with every older compiler. The configured GitHub Actions workflow requires Xcode 27.0 build 27A266a and Swift 6.4, runs the deterministic test suite with complete strict-concurrency checking and warnings as errors, and builds the iOS Simulator product.

Run locally from the package root:

```sh
# Set DEVELOPER_DIR to your installed Xcode 27.0 Contents/Developer directory.
xcodebuild -version
xcrun swiftc --version
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swift package resolve
xcrun swift build --triple arm64-apple-macosx14.0 \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors
xcrun swift test --triple arm64-apple-macosx14.0 \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors
xcodebuild -scheme CommonNetworking \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/CommonNetworking \
  SDKROOT=iphonesimulator CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

Tests use an injected `URLProtocol` fixture and local synthetic responses. They do not call live endpoints. The package is intended to be validated against the exact toolchain selected in CI before cutting a release.

## License

CommonNetworking is licensed under the [MIT License](LICENSE), copyright Anurag Chourasia.

## Complete HTTP diagnostics

```swift
#if DEBUG
let logger: HTTPLogger? = .console
#else
let logger: HTTPLogger? = nil
#endif
let client = HTTPClient(session: session, logger: logger)
```

Each exchange prints HTTP REQUEST followed by HTTP RESPONSE (or HTTP ERROR), with a shared full UUID, method, redacted URL, headers and body. Responses add final URL, HTTP status and elapsed transport time in milliseconds. Non-2xx and non-HTTP response bodies are logged before validation. Cancellation and transport errors retain their existing thrown semantics. Error descriptions/userInfo are omitted because they can contain credentials.

JSON is pretty-printed with sorted keys. Headers, URL user/password/query/fragment, JSON keys at any nesting level, and URL-encoded form keys are redacted for common credentials and email. Key matching is case-insensitive and ignores punctuation. Add application-specific sensitive keys without removing defaults:

```swift
let logger = HTTPLogger(additionalSensitiveKeys: ["accountNumber", "X-Custom-Secret"]) { record in
    // Send the COMPLETE record to your thread-safe file or diagnostics sink.
    // A file sink should report write failures and define its retention policy.
}
```

There is **no body-size cutoff**. The console sink serializes complete events under a lock and emits Unicode-safe chunks without dropping or shortening content. A custom sink receives each complete record in one call and must support concurrent callers. Xcode/terminal retention and downstream log collectors can still discard output; the package cannot guarantee their retention. Logging large payloads requires memory and I/O proportional to payload size and is deliberately opt-in (nil by default).

Empty bodies are marked empty. UTF-8 non-JSON bodies are emitted as text; other bytes are emitted as full Base64. Key-based redaction cannot identify secrets inside arbitrary text, malformed JSON, binary, multipart data, or URL path segments: use a suitable custom diagnostics policy for those endpoints. Request body streams are never consumed, and are clearly marked unavailable. Logged request headers/body are from the caller's URLRequest; URLSession-added cookies/headers, redirect-hop bodies, and internally streamed bytes are not captured. The final response data and headers are captured in full, subject to redaction. No request, response, or sensitive value is modified on the wire.

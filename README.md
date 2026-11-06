# CommonNetworkingKit

A lightweight, Foundation-only Swift package providing a secure, concurrent HTTP transport layer, redacting telemetry, and typed JSON decoding for multi-app architectures.

![Platform](https://img.shields.io/badge/Platform-iOS%2016.0%2B%20%7C%20macOS%2014.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange)
![Toolchain](https://img.shields.io/badge/Xcode-27.1-purple)
![CI](https://img.shields.io/badge/CI-Passing-brightgreen)
![SwiftLint](https://img.shields.io/badge/SwiftLint-0.65.1%20Strict-green)
![Version](https://img.shields.io/badge/Release-v2.0.0-blueviolet)
![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero%20(Pure%20Foundation)-success)
![License](https://img.shields.io/badge/License-MIT-lightgrey)

---

## 1. Executive Summary & Purpose

`CommonNetworkingKit` establishes an enterprise-grade, deterministic HTTP networking engine across **ShowBook**, **myTV**, and **Motivation Daily**. It replaces third-party dependencies with native Swift Concurrency (`async`/`await`) and injected `URLSession` instances.

### Key Engineering Objectives:
- **Clean Transport Abstraction**: `HTTPClientProtocol` provides a minimal interface separating raw HTTP transport (`send(_:)`) from typed model parsing (`request(_:as:decoder:)`).
- **Deterministic Error Handling**: `HTTPClientError` explicitly classifies transport timeouts, non-2xx status codes (`unsuccessfulStatus`), and empty payloads (`emptyBody`), retaining the raw HTTP response for error diagnostics.
- **Privacy-Preserving Telemetry**: `HTTPLogger` automatically redacts sensitive headers (e.g. `Authorization`, `Cookie`, `Set-Cookie`) and secret query parameters before logging.
- **100% Deterministic Testing**: Injected `URLSession` allows mock `URLProtocol` handlers to simulate offline states, 429 rate-limits, and payload corruptions without network calls.

---

## 2. Architecture & Design Principles

```mermaid
flowchart TD
    Consumer["Feature Service (Open Library / IPTV / Quotes API)"] -->|Builds URLRequest| Client["HTTPClient (Sendable)"]
    Client -->|Optional Diagnostic Logging| Logger["HTTPLogger (Redacting & Chunked)"]
    Client -->|Delegates Transport| Session["URLSession (Injected / Ephemeral / Shared)"]
    Session -->|Data & Response| Client
    Client -->|Success 2xx| Decoder["JSONDecoder (Typed Model Decoding)"]
    Client -->|Raw Payload| HTTPResponse["HTTPResponse (Data, Headers, Status)"]
    Client -->|Transport / Status Failures| ErrorHandling["HTTPClientError"]
```

### Architectural Tenets:
1. **Swift 6 Strict Concurrency**: All core networking interfaces, responses, and errors conform to `Sendable`. Decoders are instantiated per-call to eliminate data races.
2. **Zero Third-Party Dependencies**: Built exclusively on Apple's `Foundation` SDK.
3. **No Hidden State or Caches**: The client acts as a pure transport engine; cache lifecycles and persistence policies remain under caller ownership.

---

## 3. Dependency Graph & Consumer Matrix

| Direction | Package / Project | Responsibility |
|---|---|---|
| **Upstream Dependencies** | **FoundationKit** (`v0.2.0`) | Logging protocols and time measurement utilities. |
| **Downstream Consumers** | **ShowBook** | Powers Open Library book search, work/edition details, and cover downloads. |
| | **myTV** | Powers IPTV-org channel listings, stream verification, and broadcast categories. |
| | **Motivation Daily** | Powers multi-provider quote fetching (`Quotable`, `ZenQuotes`, `AdviceSlip`). |

---

## 4. API Contracts & Practical Code Examples

### 1. Typed Model Request with Error Handling
```swift
import Foundation
import CommonNetworkingKit

struct BookSearchService {
    private let client: HTTPClientProtocol

    init(client: HTTPClientProtocol = HTTPClient()) {
        self.client = client
    }

    func searchBooks(query: String) async throws -> SearchResultsDTO {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        let request = URLRequest(url: components.url!)
        
        do {
            return try await client.request(request, as: SearchResultsDTO.self)
        } catch let HTTPClientError.unsuccessfulStatus(status, response) {
            print("Server returned HTTP \(status): \(response)")
            throw BookServiceError.serverFailure(statusCode: status)
        } catch {
            throw BookServiceError.networkUnavailable
        }
    }
}
```

### 2. Testing with Custom `URLProtocol` Stubs
```swift
import XCTest
import CommonNetworkingKit

final class NetworkTests: XCTestCase {
    func testOfflineSimulation() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = HTTPClient(session: session)

        MockURLProtocol.stubError = URLError(.notConnectedToInternet)

        let request = URLRequest(url: URL(string: "https://api.example.com/data")!)
        
        do {
            _ = try await client.send(request)
            XCTFail("Expected failure")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }
}
```

---

## 5. Verification & Testing

```sh
# Run networking client, redacting logger, and decoder tests
swift test

# Validate swiftlint strict rules
swiftlint lint --strict
```

---

## 6. End-to-End Ecosystem Connectivity

```mermaid
graph TD
    subgraph CoreServices ["Shared Core Services (SPMs)"]
        FoundationKit["FoundationKit<br/>(System Clock, Unified Logging, Thread Safety)"]
        LocalisationKit["LocalisationKit<br/>(Typed Strings, Pluralization, String Catalogs)"]
        DesignTokensKit["DesignTokensKit<br/>(BrandPalettes, ColorTheme, Typography, Metrics, SF Symbols)"]
        CommonNetworkingKit["CommonNetworkingKit<br/>(HTTPClient, URLSession, RequestBuilder, Interceptors)"]
        AppStubData["AppStubData<br/>(Synthetic Fixtures, Offline Catalogs, Test Scenarios)"]
    end

    subgraph UIServices ["Shared Presentation & Auth (SPMs)"]
        UIComponentsKit["UIComponentsKit<br/>(CatalogTile, SurfaceCard, StateMessage, Recipes)"]
        AuthKit["AuthKit & AuthKitUI<br/>(SessionManager, AppAuthGate, AccountToolbarItem)"]
        DeveloperProfileKit["DeveloperProfileKit<br/>(DeveloperProfileView, Runtime Overlays)"]
        SnapshotTestingKit["SnapshotTestingKit<br/>(Subpixel Comparison, Golden Baseline Engine)"]
    end

    subgraph HostApps ["Host Applications"]
        ShowBook["ShowBook<br/>(Book Discovery, Core Data Persistence, Open Library)"]
        MyTV["myTV<br/>(IPTV Browser, AVPlayer Lifecycle, Directory Cache)"]
        MotivationDaily["Motivation Daily<br/>(Card Feed, Quote Persistence, Image Export Studio)"]
    end

    subgraph QualityGates ["CI/CD Automation & Tooling"]
        ArchitectureGuard["check_architecture.py<br/>(Boundary Enforcement, Zero Token Leakage)"]
        SnapshotVerifier["verify-snapshot-baselines.py<br/>(Visual Regression Gate)"]
        GHActions["GitHub Actions CI<br/>(Fast Lane, Smoke Lane, Release Build Verification)"]
    end

    %% Dependencies between Shared SPMs
    DesignTokensKit --> UIComponentsKit
    LocalisationKit --> UIComponentsKit
    DesignTokensKit --> AuthKit
    UIComponentsKit --> AuthKit
    FoundationKit --> CommonNetworkingKit
    DesignTokensKit --> DeveloperProfileKit
    UIComponentsKit --> DeveloperProfileKit
    LocalisationKit --> DeveloperProfileKit

    %% Dependencies from Host Apps to Shared SPMs
    DesignTokensKit --> ShowBook
    UIComponentsKit --> ShowBook
    AuthKit --> ShowBook
    CommonNetworkingKit --> ShowBook
    DeveloperProfileKit --> ShowBook
    AppStubData --> ShowBook

    DesignTokensKit --> MyTV
    UIComponentsKit --> MyTV
    AuthKit --> MyTV
    CommonNetworkingKit --> MyTV
    DeveloperProfileKit --> MyTV
    AppStubData --> MyTV

    DesignTokensKit --> MotivationDaily
    UIComponentsKit --> MotivationDaily
    AuthKit --> MotivationDaily
    CommonNetworkingKit --> MotivationDaily
    DeveloperProfileKit --> MotivationDaily
    AppStubData --> MotivationDaily

    %% Testing & Verification Linkage
    SnapshotTestingKit -.-> ShowBook
    SnapshotTestingKit -.-> MyTV
    SnapshotTestingKit -.-> MotivationDaily

    ArchitectureGuard --> HostApps
    ArchitectureGuard --> CoreServices
    ArchitectureGuard --> UIServices
    SnapshotVerifier --> SnapshotTestingKit
    GHActions --> HostApps
    GHActions --> UIServices
    GHActions --> CoreServices
```

---

## 7. Canonical Notion Dashboards & Governance Links

- [iOS Portfolio — Engineering Tickets Dashboard](https://app.notion.com/p/c20d7f4b133b44499c8ac0b4d5f6249e?pvs=204)
- [iOS Portfolio — Master Document](https://app.notion.com/p/40ffa5f855b98192ad2ede66a5d36fe7)
- [Architecture Boundary Validator (`check_architecture.py`)](file:///Users/anuragchourasia/Desktop/Projects/UIComponentsKit/Scripts/check_architecture.py)
- [Release & Gate Policy Documentation (`Docs/MASTER.md`)](file:///Users/anuragchourasia/Desktop/Projects/Docs/MASTER.md)

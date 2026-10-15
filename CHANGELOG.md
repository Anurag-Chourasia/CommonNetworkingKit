# Changelog

## 1.1.0

- Add opt-in HTTPLogger with paired UUIDs, elapsed transport time, sorted headers and pretty JSON.
- Redact common credentials and email in structured fields; support additional sensitive keys.
- Emit full bodies without a size limit, serialize chunked console records, and support complete-record custom sinks.
- Log failure, cancellation and non-success responses without changing HTTPClient semantics.
- Document stream/console-retention/redaction boundaries and validate multi-megabyte Unicode output.

## 1.0.0

- Prepare a Foundation-only HTTP transport as a reusable Swift package.
- Expose an injectable `URLSession` client that accepts caller-built `URLRequest` values.
- Preserve response bytes and HTTP metadata for every HTTP status through the raw API.
- Provide optional typed JSON decoding with explicit status and empty-body errors.
- Normalize URLSession transport cancellation to `CancellationError` while preserving unrelated transport and decoding errors.
- Add deterministic URLProtocol-based tests for response handling, decoding, transport errors, and cancellation.
- Add strict-concurrency and iOS Simulator validation in GitHub Actions.

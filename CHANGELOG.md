# Changelog

## 1.0.0 — Unreleased

- Prepare a Foundation-only HTTP transport as a reusable Swift package.
- Expose an injectable `URLSession` client that accepts caller-built `URLRequest` values.
- Preserve response bytes and HTTP metadata for every HTTP status through the raw API.
- Provide optional typed JSON decoding with explicit status and empty-body errors.
- Normalize URLSession transport cancellation to `CancellationError` while preserving unrelated transport and decoding errors.
- Add deterministic URLProtocol-based tests for response handling, decoding, transport errors, and cancellation.
- Add strict-concurrency and iOS Simulator validation in GitHub Actions.

Publication is pending a successful GitHub Actions run on the intended release commit.

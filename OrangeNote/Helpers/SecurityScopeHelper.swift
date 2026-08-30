//
//  SecurityScopeHelper.swift
//  OrangeNote
//
//  Provides balanced security-scoped resource access wrappers and bookmark
//  management for macOS App Sandbox file and folder operations (Task 3.11 / D023).
//

import Foundation

/// Errors that can occur during security-scoped bookmark operations.
enum SecurityScopeBookmarkError: Error, LocalizedError, Equatable {
    case creationFailed(String)
    case resolutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .creationFailed(let reason):
            return "Failed to create security-scoped bookmark: \(reason)"
        case .resolutionFailed(let reason):
            return "Failed to resolve security-scoped bookmark: \(reason)"
        }
    }
}

/// A thread-safe, RAII-style token that balances `startAccessingSecurityScopedResource()`
/// with exactly one `stopAccessingSecurityScopedResource()` call upon explicit release
/// or object deallocation.
final class SecurityScopeToken: @unchecked Sendable {
    private let accessedURLs: [URL]
    private var isReleased: Bool = false
    private let lock = NSLock()

    /// Initializes a token with an array of URLs that successfully returned `true`
    /// from `startAccessingSecurityScopedResource()`.
    init(accessedURLs: [URL]) {
        self.accessedURLs = accessedURLs
    }

    /// Whether any security scope was actively acquired and is currently held.
    var hasActiveScope: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isReleased && !accessedURLs.isEmpty
    }

    /// Number of successfully scoped URLs managed by this token.
    var activeURLCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return isReleased ? 0 : accessedURLs.count
    }

    /// Releases all acquired security scopes in reverse order of acquisition.
    /// Calling `stopAccessing()` repeatedly is safe and idempotent.
    func stopAccessing() {
        lock.lock()
        guard !isReleased else {
            lock.unlock()
            return
        }
        isReleased = true
        let urlsToRelease = accessedURLs
        lock.unlock()

        for url in urlsToRelease.reversed() {
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        stopAccessing()
    }
}

/// Helper providing balanced security-scoped resource management and bookmark utilities.
///
/// Ensures:
/// 1. `startAccessingSecurityScopedResource()` is strictly balanced with `stopAccessingSecurityScopedResource()` (D023).
/// 2. `stopAccessingSecurityScopedResource()` is only called on URLs where `startAccessingSecurityScopedResource()` returned `true`.
/// 3. Scoped operations can be managed via synchronous or asynchronous closure wrappers or RAII tokens.
/// 4. In-memory bookmark creation and resolution round-trips for security-scoped URL coordination.
enum SecurityScopeHelper {

    // MARK: - Token Acquisition

    /// Acquires security-scoped resource access for a single URL and returns a token that
    /// balances `stopAccessingSecurityScopedResource()` when released or deallocated.
    ///
    /// - Parameter url: The URL to access (file or folder).
    /// - Returns: A `SecurityScopeToken` managing the acquired scope.
    static func acquireScope(for url: URL) -> SecurityScopeToken {
        if url.startAccessingSecurityScopedResource() {
            return SecurityScopeToken(accessedURLs: [url])
        }
        return SecurityScopeToken(accessedURLs: [])
    }

    /// Acquires security-scoped resource access for multiple URLs and returns a token that
    /// balances `stopAccessingSecurityScopedResource()` on all successfully started URLs.
    ///
    /// - Parameter urls: The URLs to access.
    /// - Returns: A `SecurityScopeToken` managing all acquired scopes.
    static func acquireScope(for urls: [URL]) -> SecurityScopeToken {
        var startedURLs: [URL] = []
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                startedURLs.append(url)
            }
        }
        return SecurityScopeToken(accessedURLs: startedURLs)
    }

    // MARK: - Synchronous Scoped Closures

    /// Executes a synchronous closure within the security scope of the provided URL,
    /// ensuring `stopAccessingSecurityScopedResource()` is called when the closure completes or throws.
    ///
    /// - Parameters:
    ///   - url: The URL whose security scope to access.
    ///   - body: The closure to execute while the scope is active.
    /// - Returns: The value returned by `body`.
    static func withSecurityScope<T>(for url: URL, _ body: () throws -> T) rethrows -> T {
        let token = acquireScope(for: url)
        defer { token.stopAccessing() }
        return try body()
    }

    /// Executes a synchronous closure within the security scope of multiple URLs,
    /// ensuring `stopAccessingSecurityScopedResource()` is called on all active URLs when the closure completes or throws.
    ///
    /// - Parameters:
    ///   - urls: The array of URLs whose security scopes to access.
    ///   - body: The closure to execute while the scopes are active.
    /// - Returns: The value returned by `body`.
    static func withSecurityScope<T>(for urls: [URL], _ body: () throws -> T) rethrows -> T {
        let token = acquireScope(for: urls)
        defer { token.stopAccessing() }
        return try body()
    }

    // MARK: - Asynchronous Scoped Closures

    /// Executes an asynchronous closure within the security scope of the provided URL,
    /// ensuring `stopAccessingSecurityScopedResource()` is called when the closure finishes or throws.
    ///
    /// - Parameters:
    ///   - url: The URL whose security scope to access.
    ///   - body: The async closure to execute while the scope is active.
    /// - Returns: The value returned by `body`.
    static func withSecurityScope<T>(for url: URL, _ body: () async throws -> T) async rethrows -> T {
        let token = acquireScope(for: url)
        defer { token.stopAccessing() }
        return try await body()
    }

    /// Executes an asynchronous closure within the security scope of multiple URLs,
    /// ensuring `stopAccessingSecurityScopedResource()` is called on all active URLs when the closure finishes or throws.
    ///
    /// - Parameters:
    ///   - urls: The array of URLs whose security scopes to access.
    ///   - body: The async closure to execute while the scopes are active.
    /// - Returns: The value returned by `body`.
    static func withSecurityScope<T>(for urls: [URL], _ body: () async throws -> T) async rethrows -> T {
        let token = acquireScope(for: urls)
        defer { token.stopAccessing() }
        return try await body()
    }

    // MARK: - Bookmark Management

    /// Creates bookmark data for a URL.
    ///
    /// Attempts creation with `.withSecurityScope` first. If running outside App Sandbox or
    /// in an un-entitled unit test runner, falls back to standard bookmark creation.
    ///
    /// - Parameters:
    ///   - url: The file or folder URL to bookmark.
    ///   - isReadOnly: If `true`, requests read-only scope; otherwise read-write.
    /// - Returns: Serialized bookmark `Data`.
    /// - Throws: `SecurityScopeBookmarkError.creationFailed` if bookmark data cannot be generated.
    static func createBookmark(
        for url: URL,
        isReadOnly: Bool = false
    ) throws -> Data {
        var options: URL.BookmarkCreationOptions = [.withSecurityScope]
        if isReadOnly {
            options.insert(.securityScopeAllowOnlyReadAccess)
        }

        do {
            return try url.bookmarkData(
                options: options,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // Fallback for non-sandboxed environments / unit tests
            do {
                return try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch let fallbackError {
                throw SecurityScopeBookmarkError.creationFailed(fallbackError.localizedDescription)
            }
        }
    }

    /// Resolves bookmark data into a security-scoped URL.
    ///
    /// - Parameters:
    ///   - data: The bookmark `Data` to resolve.
    ///   - baseURL: An optional base URL for relative resolution.
    /// - Returns: A tuple containing the resolved `URL` and whether the bookmark data is stale.
    /// - Throws: `SecurityScopeBookmarkError.resolutionFailed` if resolution fails.
    static func resolveBookmark(
        data: Data,
        relativeTo baseURL: URL? = nil
    ) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: baseURL,
                bookmarkDataIsStale: &isStale
            )
            return (resolvedURL, isStale)
        } catch {
            // Fallback for non-security-scoped bookmark data
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: baseURL,
                    bookmarkDataIsStale: &isStale
                )
                return (resolvedURL, isStale)
            } catch let fallbackError {
                throw SecurityScopeBookmarkError.resolutionFailed(fallbackError.localizedDescription)
            }
        }
    }
}

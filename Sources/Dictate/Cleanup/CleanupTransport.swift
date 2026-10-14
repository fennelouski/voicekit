#if os(macOS)
import Foundation

enum CleanupTransport {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = 35
        return URLSession(configuration: configuration, delegate: CleanupRedirectPolicy(), delegateQueue: nil)
    }()

    static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let result = try await session.data(for: request)
        try Task.checkCancellation()
        guard result.0.count <= 2_000_000 else { throw OpenAICompatibleError.incompleteResponse }
        return result
    }
}

/// Stateless delegate; no mutable data crosses URLSession's callback queue.
private final class CleanupRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Configured endpoints are explicit. Do not forward transcript or auth
        // headers to a redirect target, even one that looks like the same server.
        completionHandler(nil)
    }
}
#endif

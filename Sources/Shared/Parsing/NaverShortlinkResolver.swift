import Foundation

/// Expands a `naver.me` shortlink into the full map URL that carries the
/// coordinates.
///
/// Kept apart from `NaverShareParser` so that the parser itself stays pure and
/// testable, and so the session can be injected.
struct NaverShortlinkResolver {
    enum ResolveError: Error {
        case notAShortlink
        case noRedirect
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Follows the shortlink and returns the URL it lands on.
    ///
    /// A `HEAD` is enough — we only want the redirect target, not the page —
    /// and the timeout is short because the share sheet is blocking on this and
    /// manual entry is always available as a fallback.
    func resolve(_ url: URL) async throws -> URL {
        guard NaverShareParser.isShortlink(url) else { throw ResolveError.notAShortlink }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8

        let (_, response) = try await session.data(for: request)
        guard let finalURL = (response as? HTTPURLResponse)?.url, finalURL != url else {
            throw ResolveError.noRedirect
        }
        return finalURL
    }

    /// Resolves the shortlink when there is one, then parses.
    ///
    /// Falls back to whatever the unresolved text yielded if the network call
    /// fails, so a place name is still recovered when offline.
    func parse(text: String) async -> ParsedNaverPlace {
        let direct = NaverShareParser.parse(text: text)
        guard direct.point == nil,
              let url = direct.sourceURL ?? NaverShareParser.extractURL(from: text),
              NaverShareParser.isShortlink(url) else {
            return direct
        }

        do {
            let expanded = try await resolve(url)
            var resolved = NaverShareParser.parse(url: expanded)
            // The share text names the place better than the expanded URL does.
            if resolved.name?.isEmpty ?? true { resolved.name = direct.name }
            if resolved.address?.isEmpty ?? true { resolved.address = direct.address }
            return resolved.isEmpty ? direct : resolved
        } catch {
            return direct
        }
    }
}

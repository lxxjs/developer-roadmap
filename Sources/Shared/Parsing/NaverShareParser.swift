import Foundation

/// What we managed to pull out of a Naver Map share.
///
/// Not `Sendable`: it carries a `URL`, which is not `Sendable` in
/// swift-corelibs-foundation, and nothing here crosses an actor boundary.
struct ParsedNaverPlace: Equatable {
    var name: String?
    var point: GeoPoint?
    var address: String?
    /// The URL the values came from, kept so the UI can show what was shared.
    var sourceURL: URL?

    /// A name or address but no coordinates — the caller should geocode.
    var needsGeocoding: Bool {
        point == nil && (name?.isEmpty == false || address?.isEmpty == false)
    }

    var isEmpty: Bool {
        point == nil && (name?.isEmpty ?? true) && (address?.isEmpty ?? true)
    }
}

/// Best-effort extraction of a place from a Naver Map share.
///
/// **These formats are not a published API.** Naver has changed its share URLs
/// several times, so nothing here is trusted: every candidate coordinate is
/// range-checked before it is accepted, and the extension always shows the user
/// what was parsed before saving it. When parsing yields no coordinate the
/// caller falls back to geocoding the name, and failing that to manual entry.
enum NaverShareParser {
    /// Query parameters that have carried a latitude, in the order Naver has
    /// used them.
    private static let latitudeKeys = ["lat", "latitude", "y", "clat", "dlat", "elat"]
    private static let longitudeKeys = ["lng", "lon", "longitude", "x", "clng", "dlng", "elng"]
    private static let nameKeys = ["name", "title", "query", "placeName", "dname", "ename", "q"]
    private static let addressKeys = ["address", "addr", "roadAddr", "jibunAddress"]

    /// Hosts we recognise as Naver Map shares.
    private static let knownHosts = ["naver.me", "map.naver.com", "m.map.naver.com", "map.naver.net"]

    // MARK: - Entry points

    /// Parses a shared plain-text blob, which is typically a place name on one
    /// line followed by a share link.
    static func parse(text: String) -> ParsedNaverPlace {
        var result = ParsedNaverPlace()

        if let url = extractURL(from: text) {
            result = parse(url: url)
        }

        // A bare "37.4979, 127.0276" pasted by hand.
        if result.point == nil, let point = coordinatePair(in: text) {
            result.point = point
        }

        // The leading text line names the place better than the URL usually does.
        if result.name?.isEmpty ?? true, let line = leadingTextLine(in: text) {
            result.name = line
        }
        return result
    }

    static func parse(url: URL) -> ParsedNaverPlace {
        var result = ParsedNaverPlace()
        result.sourceURL = url

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let values = Dictionary(
            items.compactMap { item -> (String, String)? in
                guard let value = item.value, !value.isEmpty else { return nil }
                return (item.name.lowercased(), value)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Note there is no raw-string coordinate scan here. Running one over the
        // URL would re-read the very numbers `coordinate(fromCenterParameter:)`
        // just refused, without its Korea check — a London `c=` parameter came
        // back through that hole. Bare pairs are only meaningful in text a
        // person typed, which `parse(text:)` handles.
        result.point = coordinate(fromQuery: values)
            ?? coordinate(fromCenterParameter: values)
        result.name = value(in: values, keys: nameKeys).flatMap(cleanedName)
            ?? placeNameFromPath(url)
        result.address = value(in: values, keys: addressKeys).flatMap(cleanedName)
        return result
    }

    /// Whether the URL needs a network round trip before it can be parsed.
    static func isShortlink(_ url: URL) -> Bool {
        (url.host?.lowercased() ?? "").hasSuffix("naver.me")
    }

    static func isNaverMapURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if url.scheme?.lowercased() == "nmap" { return true }
        return knownHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: - Coordinate strategies

    /// Explicitly named latitude/longitude parameters.
    private static func coordinate(fromQuery values: [String: String]) -> GeoPoint? {
        guard let latitude = value(in: values, keys: latitudeKeys).flatMap(Double.init),
              let longitude = value(in: values, keys: longitudeKeys).flatMap(Double.init) else {
            return nil
        }
        return validated(latitude: latitude, longitude: longitude, hint: .latitudeFirst)
    }

    /// The `c=` map-centre parameter.
    ///
    /// Its layout has changed between Naver Map versions — older builds lead
    /// with `longitude,latitude,zoom`, newer ones lead with the zoom level — so
    /// every adjacent numeric pair is tried.
    ///
    /// Unlike the named parameters, this one is positional and unlabelled, so a
    /// plain range check is not enough to trust it: `c=15.00,0,0,0,dh` would
    /// otherwise read as a valid coordinate in the Atlantic. A pair from here is
    /// only accepted when it lands on the Korean peninsula, which is where a
    /// Naver Map share points. A rejected pair costs nothing — the caller falls
    /// back to geocoding the place name.
    private static func coordinate(fromCenterParameter values: [String: String]) -> GeoPoint? {
        guard let raw = values["c"] else { return nil }
        let numbers = raw.split(separator: ",").compactMap { Double($0) }
        guard numbers.count >= 2 else { return nil }

        for index in 0..<(numbers.count - 1) {
            guard let point = validated(
                latitude: numbers[index],
                longitude: numbers[index + 1],
                hint: .longitudeFirst
            ) else { continue }
            if isInKorea(point) { return point }
        }
        return nil
    }

    /// A `lat,lng` pair appearing anywhere in a string.
    private static func coordinatePair(in text: String) -> GeoPoint? {
        let pattern = #"(-?\d{1,3}\.\d{3,})\s*[,/]\s*(-?\d{1,3}\.\d{3,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        for match in regex.matches(in: text, range: range) {
            guard match.numberOfRanges == 3,
                  let firstRange = Range(match.range(at: 1), in: text),
                  let secondRange = Range(match.range(at: 2), in: text),
                  let first = Double(text[firstRange]),
                  let second = Double(text[secondRange]) else { continue }

            if let point = validated(latitude: first, longitude: second, hint: .latitudeFirst) {
                return point
            }
        }
        return nil
    }

    // MARK: - Validation

    /// Which component a source puts first when the order is ambiguous.
    private enum Order {
        case latitudeFirst
        case longitudeFirst
    }

    /// Latitude and longitude ranges overlap, so a pair of numbers alone cannot
    /// say which is which. Both orderings are range-checked and, when both are
    /// geographically possible, the Korean-peninsula window breaks the tie —
    /// a Naver Map share is overwhelmingly likely to be in Korea. Failing that,
    /// the source's documented order is used.
    private static func validated(latitude: Double, longitude: Double, hint: Order) -> GeoPoint? {
        let direct = GeoPoint(latitude: latitude, longitude: longitude)
        let swapped = GeoPoint(latitude: longitude, longitude: latitude)

        let directOK = direct.isValid
        let swappedOK = swapped.isValid

        switch (directOK, swappedOK) {
        case (true, false):
            return direct
        case (false, true):
            return swapped
        case (true, true):
            if isInKorea(direct), !isInKorea(swapped) { return direct }
            if isInKorea(swapped), !isInKorea(direct) { return swapped }
            return hint == .latitudeFirst ? direct : swapped
        case (false, false):
            return nil
        }
    }

    /// Generous bounding box around South Korea, including Jeju and Ulleungdo.
    private static func isInKorea(_ point: GeoPoint) -> Bool {
        (33.0...38.7).contains(point.latitude) && (124.5...131.9).contains(point.longitude)
    }

    // MARK: - Text helpers

    private static func value(in values: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let found = values[key.lowercased()], !found.isEmpty {
                return found
            }
        }
        return nil
    }

    private static func cleanedName(_ raw: String) -> String? {
        let decoded = raw.removingPercentEncoding ?? raw
        let trimmed = decoded
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Newer share links carry the place name in the path, as in
    /// `/p/entry/place/1234567?placePath=...`; the numeric place id is not a name.
    private static func placeNameFromPath(_ url: URL) -> String? {
        // A shortlink's path is an opaque slug. Taking `xAbCdEf` from
        // `naver.me/xAbCdEf` as the name is worse than having no name at all,
        // because it displaces the real one from the share text and leaves
        // nothing geocodable.
        guard !isShortlink(url) else { return nil }

        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let last = segments.last else { return nil }
        if Int(last) != nil { return nil }
        if ["place", "entry", "p", "v5", "search", "directions"].contains(last.lowercased()) {
            return nil
        }
        return cleanedName(last)
    }

    /// Pulls the most relevant link out of a share.
    ///
    /// Hand-rolled rather than `NSDataDetector`, for two reasons: the detector
    /// does not exist in swift-corelibs-foundation, which would leave this
    /// untestable anywhere but Apple platforms, and an explicit pattern is
    /// easier to reason about than its heuristics.
    static func extractURL(from text: String) -> URL? {
        let schemed = matches(of: #"(?:https?|nmap)://[^\s<>"']+"#, in: text)
            .compactMap { URL(string: $0) }

        // Prefer a link we recognise over any other link in the message.
        if let naver = schemed.first(where: isNaverMapURL) { return naver }

        // Naver's share text sometimes drops the scheme.
        let bare = matches(
            of: #"(?:naver\.me|(?:m\.)?map\.naver\.com)/[^\s<>"']+"#,
            in: text
        )
        if let host = bare.first, let url = URL(string: "https://" + host) {
            return url
        }
        return schemed.first
    }

    /// Regex matches, with trailing sentence punctuation trimmed — a link at
    /// the end of a sentence would otherwise swallow the full stop.
    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let trailing = CharacterSet(charactersIn: ".,;:!?)]}\u{201d}\u{2019}")
        return regex.matches(in: text, range: range).compactMap { match in
            guard let found = Range(match.range, in: text) else { return nil }
            let trimmed = String(text[found]).trimmingCharacters(in: trailing)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// The first line that is not itself a URL — Naver's share text leads with
    /// the place name.
    private static func leadingTextLine(in text: String) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.lowercased().hasPrefix("http") || line.lowercased().hasPrefix("nmap:") { continue }
            // Strip a trailing inline link, e.g. "스타벅스 강남 https://naver.me/x".
            let withoutLink = line
                .split(separator: " ")
                .filter { !$0.lowercased().hasPrefix("http") && !$0.lowercased().hasPrefix("nmap:") }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !withoutLink.isEmpty { return withoutLink }
        }
        return nil
    }
}

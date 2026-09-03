import XCTest
#if canImport(WalkArrowCore)
@testable import WalkArrowCore
#endif

/// The share formats are unofficial, so these tests pin the behaviour we rely
/// on rather than claiming to cover every format Naver has ever shipped: a
/// coordinate is only accepted when it range-checks, and a failed parse must
/// degrade to a name we can geocode instead of to a wrong location.
final class NaverShareParserTests: XCTestCase {
    func testExplicitLatLngParameters() {
        let url = URL(string: "https://map.naver.com/v5/entry/place/1234567?lng=127.0276&lat=37.4979&name=%EA%B0%95%EB%82%A8%EC%97%AD")!
        let parsed = NaverShareParser.parse(url: url)

        XCTAssertEqual(parsed.point?.latitude ?? 0, 37.4979, accuracy: 1e-6)
        XCTAssertEqual(parsed.point?.longitude ?? 0, 127.0276, accuracy: 1e-6)
        XCTAssertEqual(parsed.name, "강남역")
    }

    /// The `c=` parameter has led with longitude in some builds and with the
    /// zoom level in others, so every adjacent pair is tried.
    func testCentreParameterWithLeadingLongitude() {
        let url = URL(string: "https://map.naver.com/v5/?c=127.0276,37.4979,15,0,0,0,dh")!
        let parsed = NaverShareParser.parse(url: url)

        XCTAssertEqual(parsed.point?.latitude ?? 0, 37.4979, accuracy: 1e-6)
        XCTAssertEqual(parsed.point?.longitude ?? 0, 127.0276, accuracy: 1e-6)
    }

    func testCentreParameterWithLeadingZoom() {
        let url = URL(string: "https://map.naver.com/p/entry/place/11111?c=15.00,0,0,0,dh&lng=126.9780&lat=37.5665")!
        let parsed = NaverShareParser.parse(url: url)

        // The named parameters win; the zoom-first centre carries no coordinate.
        XCTAssertEqual(parsed.point?.latitude ?? 0, 37.5665, accuracy: 1e-6)
        XCTAssertEqual(parsed.point?.longitude ?? 0, 126.9780, accuracy: 1e-6)
    }

    /// Latitude and longitude ranges overlap, so a swapped pair has to be
    /// caught by the range check rather than trusted. Here the check is
    /// decisive on its own: 127 is not a possible latitude.
    func testSwappedPairIsCorrected() {
        let url = URL(string: "https://map.naver.com/v5/?lat=127.0276&lng=37.4979")!
        let parsed = NaverShareParser.parse(url: url)

        XCTAssertEqual(parsed.point?.latitude ?? 0, 37.4979, accuracy: 1e-6)
        XCTAssertEqual(parsed.point?.longitude ?? 0, 127.0276, accuracy: 1e-6)
    }

    /// A zoom-first centre parameter carries no coordinate. Both orderings of
    /// its leading pair pass a plain range check, so without the Korea window
    /// this returned a point in the Gulf of Guinea.
    func testZoomFirstCentreParameterIsNotMistakenForACoordinate() {
        let url = URL(string: "https://map.naver.com/p/entry/place/11111?c=15.00,0,0,0,dh")!
        XCTAssertNil(NaverShareParser.parse(url: url).point)
    }

    func testCentreParameterOutsideKoreaIsRejected() {
        // Central London: a real coordinate, but not one a Naver share means.
        let url = URL(string: "https://map.naver.com/v5/?c=-0.1276,51.5072,15,0,0,0,dh")!
        XCTAssertNil(NaverShareParser.parse(url: url).point)
    }

    func testOutOfRangeCoordinatesAreRejected() {
        let url = URL(string: "https://map.naver.com/v5/?lat=999&lng=888")!
        XCTAssertNil(NaverShareParser.parse(url: url).point)
    }

    func testNullIslandIsRejected() {
        let url = URL(string: "https://map.naver.com/v5/?lat=0&lng=0")!
        XCTAssertNil(NaverShareParser.parse(url: url).point)
    }

    func testNumericPlaceIdIsNotUsedAsAName() {
        let url = URL(string: "https://map.naver.com/p/entry/place/1234567890")!
        let parsed = NaverShareParser.parse(url: url)
        XCTAssertNil(parsed.name, "a place id is not a name")
        XCTAssertNil(parsed.point)
    }

    /// Naver's share text is a place name followed by a shortlink. With no
    /// coordinate in hand, the name must survive so the caller can geocode it.
    func testShareTextKeepsNameForGeocoding() {
        let text = "스타벅스 강남대로점\nhttps://naver.me/xAbCdEf"
        let parsed = NaverShareParser.parse(text: text)

        XCTAssertEqual(parsed.name, "스타벅스 강남대로점")
        XCTAssertNil(parsed.point)
        XCTAssertTrue(parsed.needsGeocoding)
    }

    func testInlineLinkIsStrippedFromTheName() {
        let text = "회사 https://naver.me/xAbCdEf"
        XCTAssertEqual(NaverShareParser.parse(text: text).name, "회사")
    }

    func testBarePastedCoordinates() {
        let parsed = NaverShareParser.parse(text: "37.4979, 127.0276")
        XCTAssertEqual(parsed.point?.latitude ?? 0, 37.4979, accuracy: 1e-6)
        XCTAssertEqual(parsed.point?.longitude ?? 0, 127.0276, accuracy: 1e-6)
    }

    /// A shortlink slug must never become the place name: it would displace
    /// the real name from the share text and leave nothing to geocode.
    func testShortlinkSlugIsNotUsedAsAName() {
        let parsed = NaverShareParser.parse(url: URL(string: "https://naver.me/xAbCdEf")!)
        XCTAssertNil(parsed.name)
        XCTAssertNil(parsed.point)
    }

    func testShortlinkDetection() {
        XCTAssertTrue(NaverShareParser.isShortlink(URL(string: "https://naver.me/xAbCdEf")!))
        XCTAssertFalse(NaverShareParser.isShortlink(URL(string: "https://map.naver.com/v5/")!))
    }

    func testNaverURLRecognition() {
        XCTAssertTrue(NaverShareParser.isNaverMapURL(URL(string: "https://naver.me/x")!))
        XCTAssertTrue(NaverShareParser.isNaverMapURL(URL(string: "https://m.map.naver.com/y")!))
        XCTAssertTrue(NaverShareParser.isNaverMapURL(URL(string: "nmap://place?lat=37.5&lng=127.0")!))
        XCTAssertFalse(NaverShareParser.isNaverMapURL(URL(string: "https://maps.google.com/")!))
    }

    /// A Naver link should be preferred over any other link in the message.
    func testNaverLinkIsPickedOutOfMixedText() {
        let text = "여기 봐 https://example.com/foo 그리고 https://naver.me/xAbCdEf"
        XCTAssertEqual(
            NaverShareParser.extractURL(from: text)?.absoluteString,
            "https://naver.me/xAbCdEf"
        )
    }

    func testAppSchemeParameters() {
        let url = URL(string: "nmap://place?lat=37.5665&lng=126.9780&name=%EC%84%9C%EC%9A%B8%EC%8B%9C%EC%B0%BD")!
        let parsed = NaverShareParser.parse(url: url)
        XCTAssertEqual(parsed.point?.latitude ?? 0, 37.5665, accuracy: 1e-6)
        XCTAssertEqual(parsed.name, "서울시창")
    }

    func testGarbageInputYieldsNothingRatherThanAWrongPlace() {
        let parsed = NaverShareParser.parse(text: "")
        XCTAssertTrue(parsed.isEmpty)
        XCTAssertFalse(parsed.needsGeocoding)
    }
}

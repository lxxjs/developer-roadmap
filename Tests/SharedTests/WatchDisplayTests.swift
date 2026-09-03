import XCTest
#if canImport(WalkArrowCore)
@testable import WalkArrowCore
#endif

/// What can be checked about the watch screen without rendering it: that no
/// string the compass produces overflows the narrowest supported display, and
/// that the arrow's rotation never takes the long way round.
///
/// Not covered here, and only confirmable on a device: actual glyph metrics,
/// Always-On legibility, and how the animation feels.
final class WatchDisplayTests: XCTestCase {
    // MARK: - Display width

    func testDisplayWidthCountsHangulAsTwoCells() {
        XCTAssertEqual(DisplayText.displayWidth(""), 0)
        XCTAssertEqual(DisplayText.displayWidth("abc"), 3)
        XCTAssertEqual(DisplayText.displayWidth("강남역"), 6)
        // 강남역(3 wide = 6) + space(1) + "2"(1) + 번출구(3 wide = 6)
        XCTAssertEqual(DisplayText.displayWidth("강남역 2번출구"), 14)
        XCTAssertEqual(DisplayText.displayWidth("120 m"), 5)
    }

    // MARK: - Distance and duration budgets

    /// Every distance the app can show must fit the line it is shown on.
    func testEveryDistanceStringFitsTheBudget() {
        var samples: [Double] = [0, 1, 9, 99, 999, 1000, 1499, 9999, 10_000, 99_999, 999_999]
        samples += stride(from: 0.0, through: 5000.0, by: 37).map { $0 }

        for metres in samples {
            let text = DistanceFormatter.string(fromMetres: metres)
            XCTAssertLessThanOrEqual(
                DisplayText.displayWidth(text),
                7,
                "\(metres) m rendered as \"\(text)\""
            )
        }
    }

    func testEveryDurationStringFitsTheBudget() {
        for seconds in stride(from: 0.0, through: 36_000.0, by: 61) {
            let text = DistanceFormatter.durationString(seconds)
            XCTAssertLessThanOrEqual(
                DisplayText.displayWidth(text),
                DisplayText.captionBudget,
                "\(seconds) s rendered as \"\(text)\""
            )
        }
    }

    // MARK: - Instruction compaction

    /// The reason this exists: MapKit's Korean walking instructions do not fit.
    func testVerboseKoreanInstructionIsCutToFit() throws {
        let verbose = "테헤란로 방면으로 우회전한 다음 100미터 직진하세요"
        XCTAssertGreaterThan(
            DisplayText.displayWidth(verbose),
            DisplayText.captionBudget,
            "this fixture is only meaningful if it overflows"
        )

        let text = try XCTUnwrap(DisplayText.compactInstruction(verbose))
        XCTAssertLessThanOrEqual(DisplayText.displayWidth(text), DisplayText.captionBudget)
        XCTAssertTrue(text.hasSuffix("…"), "a cut must be visible as one")
        XCTAssertTrue(
            verbose.hasPrefix(String(text.dropLast())),
            "the kept part must be a prefix of the original, got \"\(text)\""
        )
    }

    func testShortInstructionIsLeftAlone() {
        XCTAssertEqual(DisplayText.compactInstruction("우회전"), "우회전")
        XCTAssertEqual(DisplayText.compactInstruction("  직진  "), "직진")
    }

    func testEmptyInstructionBecomesNil() {
        XCTAssertNil(DisplayText.compactInstruction(nil))
        XCTAssertNil(DisplayText.compactInstruction(""))
        XCTAssertNil(DisplayText.compactInstruction("   "))
    }

    /// Cutting mid-word is worse than cutting a word early, so a space is
    /// preferred when one is close enough to the limit.
    func testCutPrefersAWordBoundary() throws {
        let text = try XCTUnwrap(
            DisplayText.compactInstruction("turn right then continue north", limit: 20)
        )
        XCTAssertLessThanOrEqual(DisplayText.displayWidth(text), 20)
        XCTAssertFalse(
            text.dropLast().hasSuffix("t"),
            "expected a break at a space, got \"\(text)\""
        )
    }

    func testPlaceNamesAreCutToTheHeaderBudget() {
        let long = "스타벅스 강남대로점 앞 횡단보도 건너편"
        let compact = DisplayText.compactPlaceName(long)
        XCTAssertLessThanOrEqual(DisplayText.displayWidth(compact), DisplayText.headerBudget)
        XCTAssertEqual(DisplayText.compactPlaceName("회사"), "회사")
    }

    /// A single over-long word still has to come back inside the budget.
    func testUnbrokenTextIsStillCut() {
        let unbroken = String(repeating: "가", count: 40)
        let compact = DisplayText.truncate(unbroken, toDisplayWidth: 10)
        XCTAssertLessThanOrEqual(DisplayText.displayWidth(compact), 10)
        XCTAssertTrue(compact.hasSuffix("…"))
    }

    // MARK: - Arrow rotation

    /// SwiftUI interpolates between the numbers it is handed, so a wrap from
    /// 179° to -179° would sweep the arrow the whole way round. Every step the
    /// accumulator emits must be the short way.
    func testRotationNeverTakesTheLongWayRound() {
        var accumulator = RotationAccumulator()
        var previous: Double?

        // A full sweep in both directions, straddling the seam repeatedly.
        for degrees in stride(from: -540.0, through: 540.0, by: 7) {
            let wrapped = GeoMath.relativeAngle(target: GeoMath.normalizedBearing(degrees), heading: 0)
            accumulator.update(to: wrapped)
            if let previous {
                XCTAssertLessThanOrEqual(
                    abs(accumulator.value - previous),
                    180.0001,
                    "a step of more than half a turn is the long way round"
                )
            }
            previous = accumulator.value
        }
    }

    /// The accumulated value must still describe the same direction it was
    /// given, however many wraps it has been through.
    func testRotationStaysEquivalentToTheTargetAngle() {
        var accumulator = RotationAccumulator()
        let angles: [Double] = [0, 90, 179, -179, -90, 10, 170, -170, 0]

        for angle in angles {
            accumulator.update(to: angle)
            let difference = GeoMath.relativeAngle(target: angle, heading: accumulator.value)
            XCTAssertLessThan(
                abs(difference),
                0.0001,
                "accumulated \(accumulator.value) should point the same way as \(angle)"
            )
        }
    }

    func testRotationStartsAtTheFirstAngleRatherThanSpinningToIt() {
        var accumulator = RotationAccumulator()
        accumulator.update(to: 150)
        XCTAssertEqual(accumulator.value, 150, accuracy: 1e-9, "the first frame must not animate in")
    }

    /// Crossing north repeatedly must not accumulate error.
    func testRepeatedSeamCrossingsDoNotDrift() {
        var accumulator = RotationAccumulator()
        for _ in 0..<200 {
            accumulator.update(to: 179)
            accumulator.update(to: -179)
        }
        let difference = GeoMath.relativeAngle(target: -179, heading: accumulator.value)
        XCTAssertLessThan(abs(difference), 0.0001, "drifted to \(accumulator.value)")
    }
}

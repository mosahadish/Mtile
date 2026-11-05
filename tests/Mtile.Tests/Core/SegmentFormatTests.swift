// Port of tests/Wtile.Tests/Core/SegmentFormatTests.cs. Mtile's SegmentFormat takes preformatted
// string args (format specs after ':' are ignored), so the C# numeric args become strings.
import XCTest
@testable import Mtile

final class SegmentFormatTests: XCTestCase {
    func testApply_ValidFormat_SubstitutesArgs() {
        let result = SegmentFormat.apply("CPU {0}%", fallback: "CPU {0}%", ["42"])
        XCTAssertEqual(result, "CPU 42%")
    }

    func testApply_MultipleArgs_SubstitutesAllPositions() {
        let result = SegmentFormat.apply("down {0} up {1}", fallback: "{0}/{1}", ["1.2M", "512K"])
        XCTAssertEqual(result, "down 1.2M up 512K")
    }

    func testApply_MalformedFormat_FallsBackInsteadOfThrowing() {
        // {5} is out of range for a single arg -- .NET's string.Format would throw FormatException.
        let result = SegmentFormat.apply("CPU {5}%", fallback: "CPU {0}%", ["42"])
        XCTAssertEqual(result, "CPU 42%")
    }

    func testApply_UnterminatedBrace_FallsBack() {
        let result = SegmentFormat.apply("CPU {0", fallback: "CPU {0}%", ["42"])
        XCTAssertEqual(result, "CPU 42%")
    }

    func testApply_StrayClosingBrace_FallsBack() {
        let result = SegmentFormat.apply("CPU 0}%", fallback: "CPU {0}%", ["42"])
        XCTAssertEqual(result, "CPU 42%")
    }

    func testApply_EscapedBraces_AreLiteral() {
        let result = SegmentFormat.apply("{{{0}}}", fallback: "{0}", ["x"])
        XCTAssertEqual(result, "{x}")
    }

    func testApply_FormatSpec_IsIgnored() {
        let result = SegmentFormat.apply("CPU {0:0.0}%", fallback: "CPU {0}%", ["42"])
        XCTAssertEqual(result, "CPU 42%")
    }

    func testApply_RepeatedPlaceholder_SubstitutesEachTime() {
        let result = SegmentFormat.apply("{0}-{0}", fallback: "{0}", ["a"])
        XCTAssertEqual(result, "a-a")
    }

    func testApply_FallbackAlsoMalformed_ReturnsFallbackVerbatim() {
        // Wtile would throw here; Mtile must never break bar painting.
        let result = SegmentFormat.apply("{9}", fallback: "{1}", ["a"])
        XCTAssertEqual(result, "{1}")
    }
}
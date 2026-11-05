// Port of tests/Wtile.Tests/Launcher/FuzzyMatcherTests.cs
import XCTest
@testable import Mtile

final class FuzzyMatcherTests: XCTestCase {
    func testScore_SubsequenceMatch_ReturnsNonNil() {
        let cases: [(query: String, candidate: String)] = [
            ("ff", "firefox.exe"),
            ("ffx", "firefox.exe"),
            ("FF", "firefox.exe"),      // case-insensitive
            ("fire", "FireAlpaca.exe"), // case-insensitive candidate
            ("wt", "wt.exe"),
            ("", "anything.exe"),       // empty query matches everything
        ]
        for c in cases {
            XCTAssertNotNil(FuzzyMatcher.score(c.query, c.candidate), "'\(c.query)' vs '\(c.candidate)'")
        }
    }

    func testScore_EmptyQuery_ScoresZero() {
        XCTAssertEqual(FuzzyMatcher.score("", "anything.exe"), 0)
    }

    func testScore_NoMatch_ReturnsNil() {
        let cases: [(query: String, candidate: String)] = [
            ("xyz", "firefox.exe"),        // not a subsequence at all
            ("oxff", "firefox.exe"),       // right letters, wrong order
            ("firefoxpro", "firefox.exe"), // query longer than candidate
        ]
        for c in cases {
            XCTAssertNil(FuzzyMatcher.score(c.query, c.candidate), "'\(c.query)' vs '\(c.candidate)'")
        }
    }

    func testScore_PrefixMatch_RanksAboveScatteredMatch() {
        let prefixScore = FuzzyMatcher.score("fi", "firefox.exe")
        let scatteredScore = FuzzyMatcher.score("fi", "office.exe") // 'f' then 'i', scattered

        guard let prefix = prefixScore, let scattered = scatteredScore else {
            return XCTFail("expected both to match")
        }
        XCTAssertGreaterThan(prefix, scattered)
    }

    func testScore_ContiguousMatch_RanksAboveNonContiguousMatch() {
        let contiguousScore = FuzzyMatcher.score("fire", "firefox.exe")
        let nonContiguousScore = FuzzyMatcher.score("fire", "far infrared explorer.exe")

        guard let contiguous = contiguousScore, let nonContiguous = nonContiguousScore else {
            return XCTFail("expected both to match")
        }
        XCTAssertGreaterThan(contiguous, nonContiguous)
    }
}
// Port of tests/Wtile.Tests/Core/ByteRateFormatterTests.cs
import XCTest
@testable import Mtile

final class ByteRateFormatterTests: XCTestCase {
    func testFormat_MatchesExpected() {
        let cases: [(bytesPerSecond: Double, expected: String)] = [
            (0, "0B/s"),
            (512, "512B/s"),
            (1023, "1023B/s"),
            (1024, "1.0KB/s"),
            (1536, "1.5KB/s"),
            (1_048_576, "1.0MB/s"),
            (1_572_864, "1.5MB/s"),
            (1_073_741_824, "1.0GB/s"),
        ]
        for c in cases {
            XCTAssertEqual(ByteRateFormatter.format(c.bytesPerSecond), c.expected, "\(c.bytesPerSecond)")
        }
    }

    func testFormat_NegativeClampsToZero() {
        XCTAssertEqual(ByteRateFormatter.format(-100), "0B/s")
    }
}
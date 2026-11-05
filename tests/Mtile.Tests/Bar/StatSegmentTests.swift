import XCTest
@testable import Mtile

/// Text is measured at a fixed 10pt per character.
private final class TextCanvas: BarCanvas {
    var texts: [String] = []

    func measure(_ text: String) -> Double { Double(text.count) * 10 }
    func fill(_ rect: BarRect, _ color: RGBColor) {}
    func drawText(_ text: String, in rect: BarRect, color: RGBColor, alignment: BarTextAlignment) { texts.append(text) }
}

final class StatSegmentTests: XCTestCase {
    private let theme = BarTheme(BarColorsConfig())
    private let bounds = BarRect(x: 0, y: 0, width: 200, height: 24)

    private func drawn(_ segment: Segment) -> [String] {
        let canvas = TextCanvas()
        segment.draw(canvas, bounds)
        return canvas.texts
    }

    func testCpu_RoundsPercent_AndReservesWidthFor100() {
        let segment = CpuSegment(theme: theme, format: nil, percent: { 7.6 })
        XCTAssertEqual(drawn(segment), ["CPU 8%"])
        XCTAssertEqual(segment.measure(TextCanvas()), Double("CPU 100%".count) * 10 + 12)
    }

    func testMemory_TruncatesPercent_AndUsesCustomFormat() {
        XCTAssertEqual(drawn(MemorySegment(theme: theme, format: "RAM {0}", percent: { 42.9 })), ["RAM 42"])
    }

    func testMalformedFormat_FallsBackToDefault() {
        XCTAssertEqual(drawn(CpuSegment(theme: theme, format: "CPU {1}%", percent: { 5 })), ["CPU 5%"])
    }

    func testBattery_HiddenWithoutBattery() {
        let segment = BatterySegment(theme: theme, format: nil, battery: { .none })
        XCTAssertEqual(segment.measure(TextCanvas()), 0)
        XCTAssertEqual(drawn(segment), [])
    }

    func testBattery_StateWords_AndTrimsTrailingSpace() {
        func text(_ status: BatteryStatus) -> [String] { drawn(BatterySegment(theme: theme, format: nil, battery: { status })) }
        XCTAssertEqual(text(BatteryStatus(hasBattery: true, percent: 96)), ["BAT 96%"])
        XCTAssertEqual(text(BatteryStatus(hasBattery: true, percent: 50, isOnAc: true)), ["BAT 50% AC"])
        XCTAssertEqual(text(BatteryStatus(hasBattery: true, percent: 50, isCharging: true, isOnAc: true)), ["BAT 50% Charging"])
    }

    func testBattery_ReservesWidthForWidestState() {
        let segment = BatterySegment(theme: theme, format: nil, battery: { BatteryStatus(hasBattery: true, percent: 5) })
        XCTAssertEqual(segment.measure(TextCanvas()), Double("BAT 100% Charging".count) * 10 + 12)
    }

    func testNetwork_FormatsRates() {
        let segment = NetworkSegment(theme: theme, format: nil, rate: { NetworkRate(downBytesPerSec: 1536, upBytesPerSec: 10) })
        XCTAssertEqual(drawn(segment), ["↓1.5KB/s ↑10B/s"])
    }

    func testVolume_HiddenWithoutDevice_MutedShownBare() {
        XCTAssertEqual(VolumeSegment(theme: theme, format: nil, volume: { nil }).measure(TextCanvas()), 0)
        XCTAssertEqual(drawn(VolumeSegment(theme: theme, format: "V {0}", volume: { VolumeStatus(percent: 30, muted: false) })), ["V 30"])
        XCTAssertEqual(drawn(VolumeSegment(theme: theme, format: "V {0}", volume: { VolumeStatus(percent: 30, muted: true) })), ["MUTED"])
    }

    func testGpu_HiddenWithoutGpu() {
        XCTAssertEqual(GpuSegment(theme: theme, format: nil, percent: { nil }).measure(TextCanvas()), 0)
        XCTAssertEqual(drawn(GpuSegment(theme: theme, format: nil, percent: { 12.5 })), ["GPU 13%"])
    }

    #if os(macOS)
    func testFormatFor_IsCaseInsensitive_AndEmptyMeansDefault() {
        var config = BarConfig()
        var cpu = BarModuleConfig(); cpu.name = "CPU"; cpu.format = "C {0}"
        var mem = BarModuleConfig(); mem.name = "memory"
        config.modules = [cpu, mem]
        XCTAssertEqual(BarWindow.format(for: "cpu", config), "C {0}")
        XCTAssertNil(BarWindow.format(for: "memory", config))
        XCTAssertNil(BarWindow.format(for: "gpu", config))
    }
    #endif
}

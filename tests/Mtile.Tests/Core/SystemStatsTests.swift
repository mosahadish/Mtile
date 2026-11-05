import XCTest
@testable import Mtile

final class SystemStatsTests: XCTestCase {
    func testCpuLoad_FirstSampleIsZero_ThenUsesDeltas() {
        var calc = CpuLoadCalculator()
        XCTAssertEqual(calc.add(CpuTicks(busy: 500, total: 1000)), 0)
        XCTAssertEqual(calc.add(CpuTicks(busy: 575, total: 1100)), 75)
    }

    func testCpuLoad_NoElapsedTicks_IsZero_AndBackwardsCountersKeepLastValue() {
        var calc = CpuLoadCalculator()
        _ = calc.add(CpuTicks(busy: 0, total: 0))
        XCTAssertEqual(calc.add(CpuTicks(busy: 50, total: 100)), 50)
        XCTAssertEqual(calc.add(CpuTicks(busy: 50, total: 100)), 0)
        XCTAssertEqual(calc.add(CpuTicks(busy: 10, total: 20)), 0)
    }

    func testNetworkRate_DividesByElapsedSeconds() {
        var calc = NetworkRateCalculator()
        XCTAssertEqual(calc.add(rx: 1000, tx: 100, time: 10), NetworkRate())
        XCTAssertEqual(calc.add(rx: 3000, tx: 600, time: 12), NetworkRate(downBytesPerSec: 1000, upBytesPerSec: 250))
    }

    func testNetworkRate_CounterGoingBackwards_CountsAsZeroInsteadOfTrapping() {
        var calc = NetworkRateCalculator()
        _ = calc.add(rx: 5000, tx: 5000, time: 0)
        XCTAssertEqual(calc.add(rx: 100, tx: 6000, time: 1), NetworkRate(downBytesPerSec: 0, upBytesPerSec: 1000))
    }

    func testNetworkRate_SameTimestamp_KeepsLastRate() {
        var calc = NetworkRateCalculator()
        _ = calc.add(rx: 0, tx: 0, time: 0)
        let rate = calc.add(rx: 100, tx: 100, time: 1)
        XCTAssertEqual(calc.add(rx: 999, tx: 999, time: 1), rate)
    }

    func testThrottledValue_ReusesSampleWithinInterval() {
        var now = 0.0
        var calls = 0
        let value = ThrottledValue(interval: 0.5, clock: { now }) { () -> Int in calls += 1; return calls }
        XCTAssertEqual(value.value, 1)
        now = 0.4
        XCTAssertEqual(value.value, 1)
        now = 0.5
        XCTAssertEqual(value.value, 2)
    }

    func testMemoryPercent_IsAppPlusWiredPlusCompressedOverTotal() {
        let percent = SystemStats.memoryPercent(internalPages: 300, purgeablePages: 100, wiredPages: 150,
                                                compressedPages: 50, pageSize: 4096, totalBytes: 1000 * 4096)
        XCTAssertEqual(percent, 40, accuracy: 0.0001)
    }

    func testMemoryPercent_ZeroTotal_IsZero_AndClampedTo100() {
        XCTAssertEqual(SystemStats.memoryPercent(internalPages: 1, purgeablePages: 0, wiredPages: 0, compressedPages: 0,
                                                 pageSize: 4096, totalBytes: 0), 0)
        XCTAssertEqual(SystemStats.memoryPercent(internalPages: 10, purgeablePages: 20, wiredPages: 5000, compressedPages: 0,
                                                 pageSize: 4096, totalBytes: 4096), 100)
    }

    #if os(macOS)
    func testLiveSamplers_ReturnSaneValues() {
        XCTAssertNotNil(SystemSampler.cpuTicks())
        XCTAssertNotNil(SystemSampler.interfaceTotals())
        let memory = try? XCTUnwrap(SystemSampler.memoryPercent())
        XCTAssertTrue((0...100).contains(memory ?? -1))
        let battery = SystemSampler.battery()
        if battery.hasBattery { XCTAssertTrue((0...100).contains(battery.percent)) }
        if let gpu = SystemSampler.gpuPercent() { XCTAssertTrue((0...100).contains(gpu)) }
        if let volume = VolumeSampler.sample() { XCTAssertTrue((0...100).contains(volume.percent)) }
    }
    #endif
}

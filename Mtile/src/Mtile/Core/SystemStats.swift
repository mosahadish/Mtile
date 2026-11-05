import Foundation

/// Battery state for BatterySegment. `hasBattery` is false on a desktop Mac (no internal battery)
/// or when the state is unknown -- callers must render nothing then, not a garbage percent.
public struct BatteryStatus: Equatable {
    public var hasBattery: Bool
    public var percent: Int
    public var isCharging: Bool
    public var isOnAc: Bool

    public init(hasBattery: Bool = false, percent: Int = 0, isCharging: Bool = false, isOnAc: Bool = false) {
        self.hasBattery = hasBattery
        self.percent = percent
        self.isCharging = isCharging
        self.isOnAc = isOnAc
    }

    public static let none = BatteryStatus()
}

public struct NetworkRate: Equatable {
    public var downBytesPerSec: Double
    public var upBytesPerSec: Double

    public init(downBytesPerSec: Double = 0, upBytesPerSec: Double = 0) {
        self.downBytesPerSec = downBytesPerSec
        self.upBytesPerSec = upBytesPerSec
    }
}

/// Cumulative CPU tick counters (all cores summed). `busy` excludes idle.
public struct CpuTicks: Equatable {
    public var busy: UInt64
    public var total: UInt64

    public init(busy: UInt64, total: UInt64) {
        self.busy = busy
        self.total = total
    }
}

/// Turns successive cumulative CPU tick samples into a 0-100 percent. The first sample has no
/// baseline and yields 0, as in Wtile.
public struct CpuLoadCalculator {
    private var last: CpuTicks?
    public private(set) var percent = 0.0

    public init() {}

    public mutating func add(_ ticks: CpuTicks) -> Double {
        if let last {
            let total = ticks.total &- last.total
            let busy = ticks.busy &- last.busy
            // Counters going backwards (shouldn't happen) would otherwise wrap to huge values.
            if ticks.total >= last.total, ticks.busy >= last.busy {
                percent = total == 0 ? 0 : min(100, 100 * Double(busy) / Double(total))
            }
        }
        last = ticks
        return percent
    }
}

/// Turns successive cumulative rx/tx byte totals into bytes/sec. A counter that went backwards
/// (an interface disappeared from the sum) counts as zero traffic for that interval instead of
/// trapping on unsigned underflow.
public struct NetworkRateCalculator {
    private var last: (rx: UInt64, tx: UInt64, time: TimeInterval)?
    public private(set) var rate = NetworkRate()

    public init() {}

    public mutating func add(rx: UInt64, tx: UInt64, time: TimeInterval) -> NetworkRate {
        if let last, time > last.time {
            let elapsed = time - last.time
            let down = rx >= last.rx ? Double(rx - last.rx) / elapsed : 0
            let up = tx >= last.tx ? Double(tx - last.tx) / elapsed : 0
            rate = NetworkRate(downBytesPerSec: down, upBytesPerSec: up)
        }
        last = (rx, tx, time)
        return rate
    }
}

/// Caches a sampled value for `interval` seconds. Measure and Draw both read stats within one
/// repaint, and repaints also fire on every window-manager change (which can burst far faster
/// than 1Hz) -- without this, CPU/network deltas would be taken microseconds apart (~0) and the
/// system would be re-polled far more often than needed. Same reasoning as Wtile's SystemStats.
public final class ThrottledValue<T> {
    private let interval: TimeInterval
    private let clock: () -> TimeInterval
    private let sample: () -> T
    private var lastSampleTime: TimeInterval?
    private var cached: T?

    public init(interval: TimeInterval, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                sample: @escaping () -> T) {
        self.interval = interval
        self.clock = clock
        self.sample = sample
    }

    public var value: T {
        let now = clock()
        if let cached, let lastSampleTime, now - lastSampleTime < interval { return cached }
        let fresh = sample()
        cached = fresh
        lastSampleTime = now
        return fresh
    }
}

/// Shared system polling for the bar's cpu/memory/battery/network/gpu segments. Static and
/// process-lifetime (like Wtile's SystemStats) rather than per segment: every monitor's bar has
/// its own segment instances, recreated on each config reload, but they all read one set of
/// "last sample" state here, so a reload doesn't reset delta tracking and multiple bars don't
/// re-poll and jitter against each other.
public enum SystemStats {
    static let minSampleInterval: TimeInterval = 0.5

    public static func cpuPercent() -> Double { cpu.value }
    public static func memoryPercent() -> Double { memory.value }
    public static func battery() -> BatteryStatus { batteryValue.value }
    public static func networkRate() -> NetworkRate { network.value }
    /// nil when no GPU reports utilization (e.g. some VMs) -- GpuSegment renders nothing then.
    public static func gpuPercent() -> Double? { gpu.value }

    private static var cpuCalculator = CpuLoadCalculator()
    private static let cpu = ThrottledValue(interval: minSampleInterval) { () -> Double in
        guard let ticks = SystemSampler.cpuTicks() else { return cpuCalculator.percent }
        return cpuCalculator.add(ticks)
    }

    private static let memory = ThrottledValue(interval: minSampleInterval) { SystemSampler.memoryPercent() ?? 0 }
    private static let batteryValue = ThrottledValue(interval: minSampleInterval) { SystemSampler.battery() }

    private static var networkCalculator = NetworkRateCalculator()
    private static let network = ThrottledValue(interval: minSampleInterval) { () -> NetworkRate in
        guard let totals = SystemSampler.interfaceTotals() else { return networkCalculator.rate }
        return networkCalculator.add(rx: totals.rx, tx: totals.tx, time: ProcessInfo.processInfo.systemUptime)
    }

    private static let gpu = ThrottledValue(interval: minSampleInterval) { SystemSampler.gpuPercent() }

    /// Activity Monitor's "Memory Used" (app memory + wired + compressed) as a share of physical RAM.
    static func memoryPercent(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64,
                              compressedPages: UInt64, pageSize: UInt64, totalBytes: UInt64) -> Double {
        guard totalBytes > 0 else { return 0 }
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let used = Double(appPages + wiredPages + compressedPages) * Double(pageSize)
        return min(100, max(0, 100 * used / Double(totalBytes)))
    }
}

#if os(macOS)
import Darwin
import IOKit
import IOKit.ps

/// The raw macOS reads behind SystemStats. Each returns nil/`.none` on failure rather than throwing,
/// since it runs inside bar painting.
enum SystemSampler {
    static func cpuTicks() -> CpuTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return CpuTicks(busy: user + system + nice, total: user + system + idle + nice)
    }

    static func memoryPercent() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        return SystemStats.memoryPercent(internalPages: UInt64(stats.internal_page_count),
                                         purgeablePages: UInt64(stats.purgeable_count),
                                         wiredPages: UInt64(stats.wire_count),
                                         compressedPages: UInt64(stats.compressor_page_count),
                                         pageSize: UInt64(pageSize),
                                         totalBytes: ProcessInfo.processInfo.physicalMemory)
    }

    static func battery() -> BatteryStatus {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return .none }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  desc[kIOPSIsPresentKey] as? Bool ?? true,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let percent = Swift.min(100, Swift.max(0, Int((100 * Double(current) / Double(max)).rounded())))
            return BatteryStatus(hasBattery: true, percent: percent,
                                 isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                                 isOnAc: desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return .none
    }

    /// Sums 64-bit byte counters across every up, running, non-loopback interface (Wtile sums
    /// operationally-up, non-loopback adapters). Uses NET_RT_IFLIST2 rather than getifaddrs,
    /// whose if_data counters are 32-bit and wrap every 4GB.
    static func interfaceTotals() -> (rx: UInt64, tx: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var rx: UInt64 = 0, tx: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let flags = Int32(msg.ifm_flags)
                    let isActive = flags & IFF_UP != 0 && flags & IFF_RUNNING != 0
                    if isActive && flags & IFF_LOOPBACK == 0 {
                        rx &+= msg.ifm_data.ifi_ibytes
                        tx &+= msg.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (rx, tx)
    }

    /// Highest "Device Utilization %" reported by any IOAccelerator (the GPU driver's own
    /// performance statistics -- the same number Activity Monitor's GPU history shows).
    static func gpuPercent() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                  let utilization = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber
            else { continue }
            best = Swift.max(best ?? 0, Swift.min(100, Swift.max(0, utilization.doubleValue)))
        }
        return best
    }
}
#else
enum SystemSampler {
    static func cpuTicks() -> CpuTicks? { nil }
    static func memoryPercent() -> Double? { nil }
    static func battery() -> BatteryStatus { .none }
    static func interfaceTotals() -> (rx: UInt64, tx: UInt64)? { nil }
    static func gpuPercent() -> Double? { nil }
}
#endif

import Foundation

/// Formats a bytes/sec rate as a short human string (1024-based), e.g. "512B/s", "1.2MB/s".
/// Same output as Wtile's ByteRateFormatter.
public enum ByteRateFormatter {
    private static let kilo = 1024.0
    private static let mega = kilo * 1024
    private static let giga = mega * 1024

    public static func format(_ bytesPerSecond: Double) -> String {
        let b = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        if b < kilo { return "\(Int(b))B/s" }
        if b < mega { return oneDecimal(b / kilo) + "KB/s" }
        if b < giga { return oneDecimal(b / mega) + "MB/s" }
        return oneDecimal(b / giga) + "GB/s"
    }

    // .NET's "0.0" custom format rounds half away from zero.
    private static func oneDecimal(_ value: Double) -> String {
        let tenths = (value * 10).rounded(.toNearestOrAwayFromZero)
        return "\(Int(tenths) / 10).\(Int(tenths) % 10)"
    }
}

import Foundation

public struct VolumeStatus: Equatable {
    public var percent: Int
    public var muted: Bool

    public init(percent: Int, muted: Bool) {
        self.percent = percent
        self.muted = muted
    }
}

/// Reads the default output device's volume and mute state via Core Audio. Unlike Wtile (which
/// caches the endpoint for the process lifetime), the default device is looked up on every
/// sample, so switching outputs (e.g. plugging in headphones) is picked up right away.
public enum VolumeStats {
    /// nil when there's no default output device or it has no readable volume -- VolumeSegment
    /// renders nothing then, the same "hide on absence" rule as a missing battery.
    public static func volume() -> VolumeStatus? { cached.value }

    private static let cached = ThrottledValue(interval: 0.25) { VolumeSampler.sample() }
}

#if os(macOS)
import CoreAudio
import AudioToolbox

enum VolumeSampler {
    static func sample() -> VolumeStatus? {
        guard let device = defaultOutputDevice(), let level = volumeScalar(device) else { return nil }
        let muted = readUInt32(device, kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain).map { $0 != 0 } ?? false
        return VolumeStatus(percent: Int((Double(level) * 100).rounded()), muted: muted)
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// The device's overall volume: the "virtual main" volume the menu-bar slider drives, else the
    /// main element's scalar, else the average of the first two channels (common on USB/HDMI).
    private static func volumeScalar(_ device: AudioDeviceID) -> Float32? {
        if let v = readFloat(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, element: kAudioObjectPropertyElementMain) {
            return v
        }
        if let v = readFloat(device, kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return v
        }
        let channels = [1, 2].compactMap { readFloat(device, kAudioDevicePropertyVolumeScalar, element: AudioObjectPropertyElement($0)) }
        return channels.isEmpty ? nil : channels.reduce(0, +) / Float32(channels.count)
    }

    private static func readFloat(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Float32? {
        var value = Float32(0)
        return read(device, selector, element: element, into: &value) ? value : nil
    }

    private static func readUInt32(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> UInt32? {
        var value = UInt32(0)
        return read(device, selector, element: element, into: &value) ? value : nil
    }

    private static func read<T>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                                element: AudioObjectPropertyElement, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutableBytes(of: &value) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0.baseAddress!) } == noErr
    }
}
#else
enum VolumeSampler {
    static func sample() -> VolumeStatus? { nil }
}
#endif

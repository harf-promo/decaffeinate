import CoreAudio
import Foundation

/// One enumerated audio device (the seam's value type — no CoreAudio in tests).
struct AudioDeviceInfo: Sendable, Hashable {
    let uid: String  // kAudioDevicePropertyDeviceUID
    let name: String  // kAudioObjectPropertyName
    let hasInput: Bool
    let hasOutput: Bool
}

/// Resolves an IOKit audio resource token (a device UID/UUID or built-in name)
/// to a friendly device name ("AirPods Pro", "Built-in Microphone"). Mirrors the
/// `ProcessProvenanceResolving` seam: lazy, cached, render-only, never traps.
@MainActor
protocol AudioDeviceResolving {
    func friendlyName(forToken token: String) -> String?
    func device(forToken token: String) -> AudioDeviceInfo?
}

@MainActor
final class AudioDeviceResolver: AudioDeviceResolving {
    private let enumerate: () -> [AudioDeviceInfo]
    private let now: () -> Date
    private let ttl: TimeInterval = 30  // the device set changes slowly
    private var cache: [AudioDeviceInfo]?
    private var cachedAt: Date?

    init(
        enumerate: @escaping () -> [AudioDeviceInfo] = CoreAudioDeviceEnumerator.enumerate,
        now: @escaping () -> Date = { Date() }
    ) {
        self.enumerate = enumerate
        self.now = now
    }

    func device(forToken token: String) -> AudioDeviceInfo? {
        let t = token.lowercased()
        return devicesCached().first { $0.uid.lowercased() == t || $0.name.lowercased() == t }
    }

    func friendlyName(forToken token: String) -> String? {
        if let pretty = Self.prettifyBuiltIn(token) { return pretty }
        if let hit = device(forToken: token) { return hit.name }
        return Self.prettifyUnknown(token)
    }

    private func devicesCached() -> [AudioDeviceInfo] {
        if let cache, let at = cachedAt, now().timeIntervalSince(at) < ttl { return cache }
        let fresh = enumerate()
        cache = fresh
        cachedAt = now()
        return fresh
    }

    /// Built-in tokens prettify without any CoreAudio call (table-driven, pure).
    static func prettifyBuiltIn(_ token: String) -> String? {
        switch token {
        case "BuiltInSpeakerDevice": return "Built-in Speakers"
        case "BuiltInMicrophoneDevice": return "Built-in Microphone"
        case "BuiltInHeadphoneOutputDevice", "BuiltInHeadphoneDevice": return "Headphones"
        default: return nil
        }
    }

    /// A bare UUID → nil (don't surface noise); a name-like token → trimmed.
    static func prettifyUnknown(_ token: String) -> String? {
        if looksLikeUUID(token) { return nil }
        let trimmed = ReasonEngine.sanitize(token, maxLength: 64)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func looksLikeUUID(_ s: String) -> Bool {
        if UUID(uuidString: s) != nil { return true }
        return s.count >= 16 && s.allSatisfy { $0.isHexDigit || $0 == "-" }
    }
}

/// Live CoreAudio enumeration — public API, no entitlement. Every call degrades
/// to `[]` on any non-`noErr` status (never traps).
enum CoreAudioDeviceEnumerator {
    static func enumerate() -> [AudioDeviceInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard
            AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr,
            dataSize > 0
        else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }

        return ids.compactMap { id in
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = stringProperty(id, kAudioObjectPropertyName) ?? uid
            return AudioDeviceInfo(
                uid: uid, name: name,
                hasInput: hasStreams(id, scope: kAudioObjectPropertyScopeInput),
                hasOutput: hasStreams(id, scope: kAudioObjectPropertyScopeOutput))
        }
    }

    private static func stringProperty(
        _ id: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
            let cfString = value?.takeRetainedValue()
        else { return nil }
        let string = cfString as String
        return string.isEmpty ? nil : string
    }

    private static func hasStreams(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else {
            return false
        }
        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }
}

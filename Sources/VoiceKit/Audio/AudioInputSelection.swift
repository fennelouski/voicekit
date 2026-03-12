//
//  AudioInputSelection.swift
//  VoiceKit
//
//  Enumerates and applies audio input device (and input/channel) selection.
//

import AVFoundation
import Foundation

#if os(macOS)
import CoreAudio
#endif

/// A selectable audio input device.
public struct SelectableDevice: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A selectable audio input (data source) within a device.
public struct SelectableInput: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Protocol for persisting audio input device/input selection.
/// Provide a custom implementation to change where selections are stored.
public protocol AudioInputStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

/// Default implementation using UserDefaults.
public struct UserDefaultsAudioInputStorage: AudioInputStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "voiceKit_") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: keyPrefix + key)
    }

    public func set(_ value: String?, forKey key: String) {
        defaults.set(value, forKey: keyPrefix + key)
    }
}

private enum StorageKeys {
    static let deviceId = "deviceId"
    static let inputId = "inputId"
}

/// Enumerates and applies audio input device selection.
public enum AudioInputSelection {
    /// Available input devices. On iOS these are ports; on macOS these are Core Audio input devices.
    public static func availableDevices() async -> [SelectableDevice] {
        #if os(iOS) || os(visionOS)
        return await availableDevicesIOS()
        #elseif os(macOS)
        return availableDevicesMacOS()
        #endif
    }

    /// Available inputs (data sources) for the given device. On macOS returns a single "Default input" if any.
    public static func availableInputs(for device: SelectableDevice) async -> [SelectableInput] {
        #if os(iOS) || os(visionOS)
        return await availableInputsIOS(for: device)
        #elseif os(macOS)
        return [SelectableInput(id: "default", name: "Default input")]
        #endif
    }

    /// Apply preferred device/input before starting capture. On iOS sets AVAudioSession; on macOS the caller must pass deviceID to the engine.
    public static func applyPreferredInput(device: SelectableDevice?, input: SelectableInput?) {
        #if os(iOS) || os(visionOS)
        applyPreferredInputIOS(device: device, input: input)
        #endif
    }

    /// Save the current device/input selection.
    public static func saveSelection(device: SelectableDevice?, input: SelectableInput?, storage: AudioInputStorage = UserDefaultsAudioInputStorage()) {
        storage.set(device?.id, forKey: StorageKeys.deviceId)
        storage.set(input?.id, forKey: StorageKeys.inputId)
    }

    /// Load the saved device ID.
    public static func loadSelectedDeviceId(storage: AudioInputStorage = UserDefaultsAudioInputStorage()) -> String? {
        storage.string(forKey: StorageKeys.deviceId)
    }

    /// Load the saved input ID.
    public static func loadSelectedInputId(storage: AudioInputStorage = UserDefaultsAudioInputStorage()) -> String? {
        storage.string(forKey: StorageKeys.inputId)
    }

    #if os(iOS) || os(visionOS)
    private static func availableDevicesIOS() async -> [SelectableDevice] {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            return []
        }
        defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
        guard let inputs = session.availableInputs else { return [] }
        return inputs.enumerated().map { i, port in
            SelectableDevice(id: "\(i):\(port.portName)", name: port.portName)
        }
    }

    private static func availableInputsIOS(for device: SelectableDevice) async -> [SelectableInput] {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            return []
        }
        defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
        guard let inputs = session.availableInputs else { return [] }
        let idx = device.id.split(separator: ":").first.flatMap { Int($0) } ?? 0
        guard idx >= 0, idx < inputs.count else { return [] }
        let port = inputs[idx]
        let sources = port.dataSources ?? []
        if sources.isEmpty {
            return [SelectableInput(id: "default", name: "Default")]
        }
        return sources.enumerated().map { i, ds in
            SelectableInput(id: "\(device.id):\(i):\(ds.dataSourceID)", name: ds.dataSourceName)
        }
    }

    private static func applyPreferredInputIOS(device: SelectableDevice?, input: SelectableInput?) {
        let session = AVAudioSession.sharedInstance()
        guard let device, let inputs = session.availableInputs else { return }
        let idx = device.id.split(separator: ":").first.flatMap { Int($0) } ?? 0
        guard idx >= 0, idx < inputs.count else { return }
        let port = inputs[idx]
        try? session.setPreferredInput(port)
        guard let sources = port.dataSources, !sources.isEmpty, let input else { return }
        let parts = input.id.split(separator: ":")
        if parts.count >= 3, let i = Int(parts[1]), i >= 0, i < sources.count {
            try? session.setInputDataSource(sources[i])
        }
    }
    #endif

    #if os(macOS)
    private static func availableDevicesMacOS() -> [SelectableDevice] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var err = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard err == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIds = [AudioDeviceID](repeating: 0, count: count)
        var dataSize = size
        err = deviceIds.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return noErr }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                base
            )
        }
        guard err == noErr else { return [] }
        var result = [SelectableDevice]()
        for deviceId in deviceIds where deviceId != 0 {
            if let name = deviceName(deviceId) {
                result.append(SelectableDevice(id: "\(deviceId)", name: name))
            }
        }
        return result
    }

    private static func deviceName(_ deviceId: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameRef: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = withUnsafeMutablePointer(to: &nameRef) { ptr in
            AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, ptr)
        }
        guard err == noErr, let cf = nameRef else { return nil }
        return cf as String
    }
    #endif
}

//
//  AudioInputInfo.swift
//  VoiceKit
//
//  Returns current default audio input device name and input/channel label.
//

import AVFoundation
import Foundation

#if os(macOS)
import CoreAudio
#endif

/// Provides information about the current default audio input device.
public enum AudioInputInfo {
    /// Device name and input/channel name for the current default input. Placeholder if unavailable.
    public static func currentInputNames() async -> (deviceName: String, inputChannelName: String) {
        #if os(iOS) || os(visionOS)
        return await currentInputNamesIOS()
        #elseif os(macOS)
        return currentInputNamesMacOS()
        #endif
    }

    #if os(iOS) || os(visionOS)
    private static func currentInputNamesIOS() async -> (deviceName: String, inputChannelName: String) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            return ("\u{2014}", "\u{2014}")
        }
        defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }

        guard let input = session.currentRoute.inputs.first else {
            return ("\u{2014}", "\u{2014}")
        }
        let deviceName = input.portName
        let inputChannelName: String
        if let dataSource = input.selectedDataSource ?? input.dataSources?.first {
            inputChannelName = dataSource.dataSourceName
        } else {
            inputChannelName = "Default"
        }
        return (deviceName, inputChannelName)
    }
    #endif

    #if os(macOS)
    private static func currentInputNamesMacOS() -> (deviceName: String, inputChannelName: String) {
        var deviceId = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceId
        )
        guard err == noErr, deviceId != 0 else {
            return ("\u{2014}", "\u{2014}")
        }

        address.mSelector = kAudioDevicePropertyDeviceNameCFString
        address.mScope = kAudioObjectPropertyScopeGlobal
        address.mElement = kAudioObjectPropertyElementMain
        var nameRef: CFString?
        size = UInt32(MemoryLayout<CFString?>.size)
        err = withUnsafeMutablePointer(to: &nameRef) { ptr in
            AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, ptr)
        }
        guard err == noErr, let cfName = nameRef else {
            return ("\u{2014}", "Default input")
        }
        let deviceName = cfName as String
        let inputChannelName = "Default input"
        return (deviceName, inputChannelName)
    }
    #endif
}

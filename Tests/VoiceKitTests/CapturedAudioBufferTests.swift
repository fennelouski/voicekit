import AVFoundation
import Foundation
import Testing
@testable import VoiceKit

struct CapturedAudioBufferTests {
    @Test func copyKeepsCaptureTimeAndAllChannelsAfterSourceIsReused() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let original = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        original.frameLength = 4
        let channels = try #require(original.floatChannelData)
        for frame in 0..<4 { channels[0][frame] = Float(frame); channels[1][frame] = Float(frame + 10) }
        let time = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: 125.75))
        let captured = try #require(CapturedAudioBuffer.copy(original, at: time))
        channels[0][2] = -999
        channels[1][2] = -999
        let copied = try #require(captured.buffer.floatChannelData)
        #expect(copied[0][2] == 2)
        #expect(copied[1][2] == 12)
        #expect(captured.hostTime == time.hostTime)
        #expect(captured.buffer.frameLength == 4)
        #expect(CapturedAudioBuffer.copy(original, at: AVAudioTime(sampleTime: 0, atRate: 48_000)) == nil)
    }
}

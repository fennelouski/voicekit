//
//  ConfigurationCodableTests.swift
//  VoiceKitTests
//
//  Tests for PositionMapper.Configuration Codable conformance.
//

import Testing
@testable import VoiceKit

struct ConfigurationCodableTests {

    @Test func roundTripsDefaultConfiguration() throws {
        let config = PositionMapper.Configuration()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PositionMapper.Configuration.self, from: data)

        #expect(decoded.recentMatchesCapacity == config.recentMatchesCapacity)
        #expect(decoded.forwardWindow == config.forwardWindow)
        #expect(decoded.backWindow == config.backWindow)
        #expect(decoded.skipAheadThreshold == config.skipAheadThreshold)
        #expect(decoded.minimumScoreThreshold == config.minimumScoreThreshold)
        #expect(decoded.backwardJumpThreshold == config.backwardJumpThreshold)
        #expect(decoded.fillerWords == config.fillerWords)
    }

    @Test func roundTripsCustomConfiguration() throws {
        let config = PositionMapper.Configuration(
            recentMatchesCapacity: 16,
            forwardWindow: 50,
            backWindow: 10,
            skipAheadThreshold: 20,
            minimumScoreThreshold: 2.0,
            backwardJumpThreshold: 8.0,
            fillerWords: ["um", "like"]
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PositionMapper.Configuration.self, from: data)

        #expect(decoded.recentMatchesCapacity == 16)
        #expect(decoded.forwardWindow == 50)
        #expect(decoded.backWindow == 10)
        #expect(decoded.skipAheadThreshold == 20)
        #expect(decoded.minimumScoreThreshold == 2.0)
        #expect(decoded.backwardJumpThreshold == 8.0)
        #expect(decoded.fillerWords == ["um", "like"])
    }

    @Test func coldStartThresholdDerived() throws {
        let config = PositionMapper.Configuration(minimumScoreThreshold: 3.0)
        #expect(config.coldStartScoreThreshold == 1.0)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PositionMapper.Configuration.self, from: data)
        #expect(decoded.coldStartScoreThreshold == 1.0)
    }
}

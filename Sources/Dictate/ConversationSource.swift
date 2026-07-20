//
//  ConversationSource.swift
//  Dictate
//
//  One audio input in a conversation recording session: a microphone or another
//  app's audio, assigned to a display name ("Nathan", "Zoom call"). The roster
//  lives in UserDefaults as JSON under Settings.conversationSourcesKey.
//

import Foundation

struct ConversationSource: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case microphone
        case app
    }

    var id: UUID
    var kind: Kind
    /// Microphone: Core Audio device UID (stable across reboots, unlike AudioDeviceID).
    /// App: bundle identifier.
    var reference: String
    /// User-assigned speaker name shown in the transcript.
    var name: String
    var enabled: Bool

    init(id: UUID = UUID(), kind: Kind, reference: String, name: String, enabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.reference = reference
        self.name = name
        self.enabled = enabled
    }
}

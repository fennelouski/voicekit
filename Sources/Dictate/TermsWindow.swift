//
//  TermsWindow.swift
//  Dictate
//
//  Clickwrap Terms of Service gate. Shown at launch whenever the user hasn't
//  accepted the current version (new install, or the terms were revised).
//  Acceptance is an explicit checkbox + button — the enforceable pattern, not a
//  bare link. Bump `TermsOfService.version` whenever the text materially changes
//  to re-prompt everyone.
//

#if os(macOS)
import AppKit
import SwiftUI

enum TermsOfService {
    /// Increment on any material change to re-prompt users who accepted an older version.
    static let version = 1
    static let lastUpdated = "July 15, 2026"

    // Canonical EULA. The website mirrors this verbatim at
    // https://nathanfennel.com/dictate/eula — keep the two in sync when editing, and bump
    // `version` on any material change. Not legal advice; have a lawyer review before relying on it.
    // ponytail: the binding legal text stays in canonical English (the version the user agrees to,
    // mirrored on the website); only the surrounding UI chrome is localized. Translate via counsel,
    // not a string table, if a localized EULA is ever required.
    static let text = """
    TERMS OF SERVICE & END USER LICENSE AGREEMENT

    Last updated: \(lastUpdated)

    These Terms of Service and End User License Agreement ("Terms") are a binding \
    agreement between you ("you" or "User") and Nathan Fennel ("we," "us," or "our") \
    governing your use of the Dictate application and any related software, updates, and \
    documentation (collectively, the "App"). By clicking "Agree & Continue," installing, \
    or using the App, you accept these Terms. If you do not agree, do not use the App.

    1. ELIGIBILITY
    You must be at least 18 years old, or the age of majority in your jurisdiction, and able \
    to form a binding contract. By using the App you represent that you meet these requirements.

    2. LICENSE
    We grant you a personal, limited, non-exclusive, non-transferable, revocable license to \
    install and use the App on devices you own or control, for your own lawful use, subject to \
    these Terms. We reserve all rights not expressly granted.

    3. HOW THE APP WORKS
    The App is a dictation tool. When you activate it, it captures audio from your microphone \
    and transcribes your speech to text. By default, speech recognition runs on your device and \
    audio is not transmitted off your device by the App. The App inserts the resulting text into \
    whatever application or field is focused on your device, using system accessibility and \
    clipboard features. The App may store a local history of your dictations and, if you enable \
    it, local transcripts of recorded conversations.

    4. OPTIONAL THIRD-PARTY AI SERVICES
    The App offers an optional "cleanup" feature. If — and only if — you choose to enable a \
    cloud-based provider and supply your own API key, the App will transmit your transcribed \
    text to that third-party provider (for example, to Anthropic, OpenAI, Google, Groq, \
    OpenRouter, or a server you configure) to process it. Your use of any third-party service is \
    governed by that provider's own terms and privacy policy. We do not control and are not \
    responsible for third-party services, their availability, their handling of your data, or any \
    charges they impose. This transmission does not occur unless you enable a cloud provider.

    5. YOUR RESPONSIBILITIES
    You are solely responsible for:
    (a) all content you dictate and everywhere the App inserts text on your behalf, and for \
    reviewing inserted text before relying on, sending, or submitting it;
    (b) how and where you use the App, including any messages, documents, code, or commands you \
    produce with it; and
    (c) complying with all laws applicable to your use.

    6. RECORDING & CONSENT
    Laws governing the recording of conversations and the capture of others' voices vary by \
    jurisdiction and often require the consent of some or all parties. You are solely responsible \
    for determining whether, and obtaining any consent required before, you record, transcribe, or \
    capture the voice of any other person using the App. You agree that we bear no responsibility \
    for your compliance with wiretapping, eavesdropping, privacy, or recording-consent laws.

    7. ACCURACY DISCLAIMER
    Speech recognition and AI processing are inherently imperfect and may produce inaccurate, \
    incomplete, or unintended text. You must review all output before relying on it. The App is \
    not intended for use in any situation where an error could lead to death, personal injury, or \
    serious physical, financial, environmental, or reputational harm, including medical, legal, \
    emergency, or safety-critical contexts. You assume all risk arising from your reliance on the \
    App's output.

    8. ACCEPTABLE USE
    You agree not to use the App to: violate any law or the rights of others; record or transcribe \
    anyone without required consent; harass, defame, or harm others; infringe intellectual property; \
    or attempt to reverse engineer, decompile, resell, or circumvent the App except to the extent \
    such restriction is prohibited by law.

    9. PRIVACY
    Our handling of information is described in our Privacy Policy at \
    https://nathanfennel.com/dictate/privacy, which is \
    incorporated by reference. By default the App processes audio on your device; data leaves your \
    device only if you enable an optional cloud feature as described in Section 4.

    10. INTELLECTUAL PROPERTY
    The App, including its software, design, and trademarks, is owned by us or our licensors and is \
    protected by law. These Terms grant you no ownership in the App. Text you produce with the App \
    is yours, subject to any rights of third parties.

    11. DISCLAIMER OF WARRANTIES
    THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTY OF ANY KIND, WHETHER EXPRESS, \
    IMPLIED, OR STATUTORY, INCLUDING WITHOUT LIMITATION THE IMPLIED WARRANTIES OF MERCHANTABILITY, \
    FITNESS FOR A PARTICULAR PURPOSE, TITLE, ACCURACY, AND NON-INFRINGEMENT. WE DO NOT WARRANT THAT \
    THE APP WILL BE UNINTERRUPTED, ERROR-FREE, SECURE, OR THAT ITS OUTPUT WILL BE ACCURATE OR \
    RELIABLE. YOU USE THE APP AT YOUR OWN RISK.

    12. LIMITATION OF LIABILITY
    TO THE MAXIMUM EXTENT PERMITTED BY LAW, IN NO EVENT WILL WE BE LIABLE FOR ANY INDIRECT, \
    INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR ANY LOSS OF PROFITS, \
    DATA, GOODWILL, OR BUSINESS, ARISING OUT OF OR RELATED TO THE APP OR THESE TERMS, EVEN IF ADVISED \
    OF THE POSSIBILITY OF SUCH DAMAGES. OUR TOTAL AGGREGATE LIABILITY FOR ALL CLAIMS RELATING TO THE \
    APP WILL NOT EXCEED THE GREATER OF THE AMOUNT YOU PAID US FOR THE APP IN THE TWELVE MONTHS BEFORE \
    THE CLAIM, OR TWENTY U.S. DOLLARS ($20).

    13. INDEMNIFICATION
    You agree to indemnify, defend, and hold harmless us and our affiliates, officers, and agents \
    from and against any claims, liabilities, damages, losses, and expenses (including reasonable \
    legal fees) arising out of or related to your use of the App, your content, or your violation of \
    these Terms or of any law or third-party right.

    14. CONSUMER RIGHTS
    Some jurisdictions do not allow the exclusion of certain warranties or the limitation of certain \
    damages. To the extent such law applies to you, some of the exclusions and limitations in \
    Sections 11 and 12 may not apply, and you may have additional rights. Nothing in these Terms \
    limits any right you have that cannot be limited under applicable law.

    15. TERMINATION
    These Terms remain in effect while you use the App. We may suspend or terminate your license at \
    any time if you breach these Terms. You may stop using the App and delete it at any time. \
    Sections 4 through 14 and 16 survive termination.

    16. CHANGES TO THE TERMS
    We may revise these Terms. When we make material changes, we will ask you to review and accept \
    the updated Terms before continuing to use the App. Your continued use after acceptance \
    constitutes agreement to the revised Terms.

    17. GOVERNING LAW & DISPUTES
    These Terms are governed by the laws of the State of Colorado, United States, without regard \
    to conflict-of-laws rules. You agree that the state and federal courts located in Colorado \
    have exclusive jurisdiction over any dispute not subject to arbitration, and you consent to \
    their jurisdiction and venue.

    18. ENTIRE AGREEMENT
    These Terms, together with the Privacy Policy, are the entire agreement between you and us \
    regarding the App and supersede any prior agreements. If any provision is held unenforceable, \
    the remaining provisions remain in effect. Our failure to enforce a provision is not a waiver.

    19. CONTACT
    Questions about these Terms: nathan@100apps.studio.

    By clicking "Agree & Continue," you acknowledge that you have read, understood, and agree to \
    be bound by these Terms of Service.
    """
}

@available(macOS 26.0, *)
@MainActor
final class TermsWindowController: NSWindowController {
    /// - Parameters:
    ///   - readOnly: reshown from a menu after acceptance; no gate, just a Close button.
    ///   - onAgree: called after acceptance is persisted (unused when readOnly).
    convenience init(readOnly: Bool, onAgree: @escaping () -> Void) {
        // No .closable on the gate: the only ways out are "Quit" or "Agree & Continue",
        // so the red X can't dismiss it without a decision.
        let style: NSWindow.StyleMask = readOnly
            ? [.titled, .closable, .fullSizeContentView]
            : [.titled, .fullSizeContentView]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: style, backing: .buffered, defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        self.init(window: window)
        window.contentViewController = NSHostingController(rootView: TermsView(
            readOnly: readOnly,
            onAgree: { [weak self] in
                Settings.acceptTerms()
                self?.close()
                onAgree()
            },
            onClose: { [weak self] in
                if readOnly { self?.close() } else { NSApp.terminate(nil) }
            }
        ))
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@available(macOS 26.0, *)
private struct TermsView: View {
    let readOnly: Bool
    let onAgree: () -> Void
    let onClose: () -> Void

    @State private var agreed = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Terms of Service")
                    .font(.system(size: 22, weight: .bold))
                Text("Please read and accept to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 14)

            ScrollView {
                Text(TermsOfService.text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.quinary))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            .padding(.horizontal, 24)

            footer
                .padding(20)
        }
        .frame(width: 640, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var footer: some View {
        if readOnly {
            HStack {
                Spacer()
                Button("Close") { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        } else {
            VStack(spacing: 14) {
                Toggle(isOn: $agreed) {
                    Text("I have read and agree to the Terms of Service.")
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button("Quit") { onClose() }
                        .controlSize(.large)
                    Spacer()
                    Button("Agree & Continue") { onAgree() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!agreed)
                }
            }
        }
    }
}
#endif

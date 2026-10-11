//
//  TranslationService.swift
//  CopyShot
//
//  Created by Mac on 26.09.26.
//

import Foundation
import NaturalLanguage
import SwiftUI
import AppKit
import Combine
#if canImport(Translation)
import Translation
#endif

/// Encapsulates translation results with source and destination language metadata.
struct TranslationResult {
    let originalText: String
    let translatedText: String
    let sourceLanguageCode: String?
    let sourceLanguageName: String
    let targetLanguageCode: String
    let targetLanguageName: String
}

#if canImport(Translation)
/// Retains invalidation state so two successive requests with the same language pair differ.
@available(macOS 15.0, *)
struct TranslationConfigurationSequence {
    private var previous: TranslationSession.Configuration?
    mutating func next(source: Locale.Language?, target: Locale.Language) -> TranslationSession.Configuration {
        var configuration: TranslationSession.Configuration
        if let previous, previous.source == source, previous.target == target { configuration = previous }
        else { configuration = TranslationSession.Configuration(source: source, target: target) }
        configuration.invalidate()
        previous = configuration
        return configuration
    }
}

@available(macOS 15.0, *)
@MainActor
private final class TranslationSessionHost: NSObject, ObservableObject, NSWindowDelegate {
    struct Request {
        let id: UUID
        let text: String
        let targetLanguageCode: String
        let targetLanguageName: String
        let configuration: TranslationSession.Configuration
    }
    @Published private var request: Request?
    private let lifetime = TranslationRequestLifetime()
    private var configurations = TranslationConfigurationSequence()
    private var operationTask: Task<Void, Never>?
    private var hostWindow: NSWindow?
    private var appearanceObserver: AnyCancellable?

    private struct HostSizeKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
    }

    struct HostView: View {
        @ObservedObject var host: TranslationSessionHost
        @ObservedObject private var settings = SettingsManager.shared
        var body: some View {
            // Capture the request identity along with the configuration, never a mutable latest payload.
            let request = host.request
            VStack(alignment: .leading, spacing: 16) {
                Label("Prepare translation languages", systemImage: "character.bubble")
                    .font(.headline)
                Text("Apple may ask to identify the source language or download a language pack for \(request?.targetLanguageName ?? "translation"). Approve its prompt to continue, or cancel this request.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for macOS…").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { host.cancelCurrentRequest() }.keyboardShortcut(.cancelAction)
                }
            }
                .padding(24).frame(width: 360).fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in Color.clear.preference(key: HostSizeKey.self, value: proxy.size) })
                .onPreferenceChange(HostSizeKey.self) { host.hostWindow?.setContentSize($0) }
                .preferredColorScheme(settings.appearance.colorScheme)
                .translationTask(request?.configuration) { session in
                    guard let request else { return }
                    await host.handleSession(session, request: request)
                }
        }
    }

    override init() {
        super.init()
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Translation Languages"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .normal
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.alphaValue = 0.01
        hostWindow = window
        let content = NSHostingView(rootView: HostView(host: self))
        window.contentView = content
        window.setContentSize(content.fittingSize)
        appearanceObserver = SettingsManager.shared.$appearance.sink { [weak window] appearance in
            switch appearance {
            case .system: window?.appearance = nil
            case .light: window?.appearance = NSAppearance(named: .aqua)
            case .dark: window?.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    func translate(id: UUID, text: String, targetLanguageCode: String,
                   completion: @escaping (Result<TranslationResult, Error>) -> Void) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(NSError(domain: "CopyShot.Translation", code: -5,
                                        userInfo: [NSLocalizedDescriptionKey: "No text found to translate."])))
            return
        }
        lifetime.start(id: id, cancelOperation: { [weak self] in
            self?.operationTask?.cancel()
            self?.operationTask = nil
            self?.request = nil
            self?.hostWindow?.orderOut(nil)
        }, completion: completion)
        let detected = TranslationService.detectLanguageCode(for: text)
        let source = detected.flatMap { $0.lowercased() == targetLanguageCode.lowercased() ? nil : Locale.Language(identifier: $0) }
        let configuration = configurations.next(source: source, target: Locale.Language(identifier: targetLanguageCode))
        request = Request(id: id, text: text, targetLanguageCode: targetLanguageCode,
                          targetLanguageName: TranslationService.localizedLanguageName(for: targetLanguageCode),
                          configuration: configuration)
        hostWindow?.alphaValue = 0.01
        hostWindow?.ignoresMouseEvents = true
        hostWindow?.orderFrontRegardless()
    }

    func cancel(id: UUID) { lifetime.cancel(id: id) }

    private func cancelCurrentRequest() {
        if let request { cancel(id: request.id) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelCurrentRequest()
        return false // Reuse the session host after cancellation.
    }

    private func showLanguagePreparation() {
        guard let hostWindow else { return }
        hostWindow.alphaValue = 1
        hostWindow.ignoresMouseEvents = false
        hostWindow.center()
        NSApp.activate(ignoringOtherApps: true)
        hostWindow.makeKeyAndOrderFront(nil)
    }

    private func handleSession(_ session: TranslationSession, request: Request) async {
        guard lifetime.isCurrent(request.id) else { return }
        let task = Task { @MainActor [weak self] in
            do {
                try Task.checkCancellation()
                let availability: LanguageAvailability.Status?
                if let source = request.configuration.source {
                    availability = await LanguageAvailability().status(from: source, to: request.configuration.target)
                } else {
                    availability = try? await LanguageAvailability().status(for: request.text, to: request.configuration.target)
                }
                try Task.checkCancellation()
                if availability != .installed && availability != .unsupported {
                    self?.showLanguagePreparation()
                }
                // translate() handles downloads and language detection. prepareTranslation()
                // cannot be used when the source is unknown because it has no sample text.
                let response = try await session.translate(request.text)
                try Task.checkCancellation()
                let source = response.sourceLanguage.minimalIdentifier
                self?.lifetime.finish(id: request.id, result: .success(TranslationResult(
                    originalText: request.text, translatedText: response.targetText,
                    sourceLanguageCode: source, sourceLanguageName: TranslationService.localizedLanguageName(for: source),
                    targetLanguageCode: request.targetLanguageCode, targetLanguageName: request.targetLanguageName)))
            } catch {
                self?.lifetime.finish(id: request.id, result: .failure(error))
            }
        }
        operationTask = task
        // SwiftUI can cancel a session when the configuration changes or its view disappears.
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}
#endif

/// Service providing on-device translation on macOS 15+ Sequoia via Apple's Translation framework and NLLanguageRecognizer.
/// Note: When translating into a language for the first time, macOS will automatically prompt the user once to download Apple's on-device language set directly.
@MainActor
final class TranslationService: ObservableObject {
    static let shared = TranslationService()
    
    #if canImport(Translation)
    private var sessionHost: AnyObject?
    #endif
    
    private init() {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            self.sessionHost = TranslationSessionHost()
        }
        #endif
    }
    
    // MARK: - Language Detection & Formatting
    
    /// Detects the dominant language code using NLLanguageRecognizer.
    nonisolated static func detectLanguageCode(for text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
    
    /// Returns the localized display name for a language code (e.g. "en" -> "English", "es" -> "Spanish").
    nonisolated static func localizedLanguageName(for code: String?) -> String {
        guard let code = code, !code.isEmpty else { return "Unknown" }
        if let name = Locale.current.localizedString(forIdentifier: code) {
            return name
        }
        if let name = Locale(identifier: "en").localizedString(forIdentifier: code) {
            return name
        }
        return code.uppercased()
    }
    
    // MARK: - Translation Execution
    
    /// Cancellation follows the action task all the way to the active framework operation.
    func translate(text: String, targetLanguageCode: String = "en") async throws -> TranslationResult {
        try Task.checkCancellation()
        #if canImport(Translation)
        if #available(macOS 15.0, *), let host = sessionHost as? TranslationSessionHost {
            let id = UUID()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                    host.translate(id: id, text: text, targetLanguageCode: targetLanguageCode) {
                        continuation.resume(with: $0)
                    }
                }
            } onCancel: {
                Task { @MainActor in host.cancel(id: id) }
            }
        }
        #endif
        throw NSError(domain: "CopyShot.Translation", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Translation requires macOS 15 or later."])
    }
}

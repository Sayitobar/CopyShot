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

private struct PendingTranslationRequest {
    let text: String
    let targetLanguageCode: String
    let targetLanguageName: String
    let sourceLanguageName: String
    let completion: (Result<TranslationResult, Error>) -> Void
}

#if canImport(Translation)
@available(macOS 15.0, *)
@MainActor
private final class TranslationSessionHost: ObservableObject {
    @Published var currentConfiguration: TranslationSession.Configuration?
    private var pendingRequest: PendingTranslationRequest?
    private var hostWindow: NSWindow?
    
    struct HostView: View {
        @ObservedObject var host: TranslationSessionHost
        
        var body: some View {
            Color.clear
                .frame(width: 1, height: 1)
                .translationTask(host.currentConfiguration) { session in
                    await host.handleSession(session)
                }
        }
    }
    
    init() {
        let hostView = NSHostingView(rootView: HostView(host: self))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostView
        window.orderBack(nil)
        self.hostWindow = window
    }
    
    func translate(
        text: String,
        targetLanguageCode: String,
        targetLanguageName: String,
        sourceLanguageName: String,
        detectedSource: String?,
        completion: @escaping (Result<TranslationResult, Error>) -> Void
    ) {
        self.pendingRequest = PendingTranslationRequest(
            text: text,
            targetLanguageCode: targetLanguageCode,
            targetLanguageName: targetLanguageName,
            sourceLanguageName: sourceLanguageName,
            completion: completion
        )
        
        let targetLang = Locale.Language(identifier: targetLanguageCode)
        let sourceLang = detectedSource != nil ? Locale.Language(identifier: detectedSource!) : nil
        
        var config = TranslationSession.Configuration(source: sourceLang, target: targetLang)
        config.invalidate()
        self.currentConfiguration = config
    }
    
    private func handleSession(_ session: TranslationSession) async {
        guard let request = pendingRequest else { return }
        self.pendingRequest = nil
        
        do {
            let response = try await session.translate(request.text)
            let detectedSourceCode = response.sourceLanguage.minimalIdentifier
            let resolvedSourceName = TranslationService.localizedLanguageName(for: detectedSourceCode)
            
            let result = TranslationResult(
                originalText: request.text,
                translatedText: response.targetText,
                sourceLanguageCode: detectedSourceCode,
                sourceLanguageName: resolvedSourceName,
                targetLanguageCode: request.targetLanguageCode,
                targetLanguageName: request.targetLanguageName
            )
            request.completion(.success(result))
        } catch {
            request.completion(.failure(error))
        }
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
    
    /// Translates the given text into the target language code.
    func translate(
        text: String,
        targetLanguageCode: String = "en",
        completion: @escaping (Result<TranslationResult, Error>) -> Void
    ) {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            guard let host = sessionHost as? TranslationSessionHost else {
                let error = NSError(
                    domain: "CopyShot.Translation",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Translation service failed to initialize."]
                )
                completion(.failure(error))
                return
            }
            
            let detectedSource = Self.detectLanguageCode(for: text)
            let sourceName = Self.localizedLanguageName(for: detectedSource)
            let targetName = Self.localizedLanguageName(for: targetLanguageCode)
            
            host.translate(
                text: text,
                targetLanguageCode: targetLanguageCode,
                targetLanguageName: targetName,
                sourceLanguageName: sourceName,
                detectedSource: detectedSource,
                completion: completion
            )
            return
        }
        #endif
        
        let error = NSError(
            domain: "CopyShot.Translation",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "On-device translation requires macOS 15.0 (Sequoia) or later."]
        )
        completion(.failure(error))
    }
}

import Foundation

enum OCRActionFactory {
    private static let caseActions: [String: QuickAction] = [
        "title_case": QuickAction(id: "title_case", title: "Title Case", icon: .typography("Aa"),
                                  shortcutNumber: 1, transform: QuickActionTransforms.toTitleCase),
        "uppercase": QuickAction(id: "uppercase", title: "UPPERCASE", icon: .typography("AA"),
                                 shortcutNumber: 2, transform: QuickActionTransforms.toUppercase),
        "lowercase": QuickAction(id: "lowercase", title: "lowercase", icon: .typography("aa"),
                                 shortcutNumber: 3, transform: QuickActionTransforms.toLowercase),
        "toggle_case": QuickAction(id: "toggle_case", title: "tOGGLE cASE", icon: .typography("aA"),
                                   shortcutNumber: 4, transform: QuickActionTransforms.toToggleCase),
        "sentence_case": QuickAction(id: "sentence_case", title: "Sentence case.", icon: .system("text.alignleft"),
                                     shortcutNumber: 5, transform: QuickActionTransforms.toSentenceCase)
    ]

    static func actions(for text: String?, config: QuickActionsConfig) -> [QuickAction] {
        let disabled = Set(config.disabledActionIds)
        return config.actionOrder.filter { !disabled.contains($0) }
            .compactMap { action(id: $0, text: text, config: config) }
            .enumerated().map { index, action in
                var numbered = action
                numbered.shortcutNumber = index + 1
                return numbered
            }
    }

    /// Builds only the requested definition; providers do not construct unrelated submenus.
    static func action(id: String, text: String?, config: QuickActionsConfig) -> QuickAction? {
        switch id {
        case "change_case":
            let order = config.subActionOrder[id] ?? ["title_case", "uppercase", "lowercase", "toggle_case", "sentence_case"]
            let disabled = Set(config.disabledSubActionIds[id] ?? [])
            let children = order.filter { !disabled.contains($0) }.compactMap { caseActions[$0] }
                .enumerated().map { index, action in
                    QuickAction(id: action.id, title: action.title, icon: action.icon,
                                shortcutNumber: index + 1, transform: action.transform)
                }
            return QuickAction(id: id, title: "Change Case", icon: .system("textformat"), shortcutNumber: 1,
                               transform: QuickActionTransforms.toTitleCase, subActions: children.isEmpty ? nil : children)
        case "join_lines":
            return QuickAction(id: id, title: "Join Lines", icon: .system("text.line.2.summary"),
                               shortcutNumber: 1, transform: QuickActionTransforms.joinLines)
        case "search_web":
            let isURL = text.map(WebActionHelper.isURL) ?? false
            return QuickAction(id: id, title: isURL ? "Open URL" : "Search Web",
                               icon: .system(isURL ? "safari" : "magnifyingglass"), shortcutNumber: 1,
                               transform: { $0 }, operation: .web(payloadIndex: nil))
        case "translate":
            guard #available(macOS 15.0, *) else { return nil }
            let children = translationSubActions(config: config)
            return QuickAction(id: id, title: "Translate (to \(config.defaultTranslateLanguage).)",
                               icon: .system("translate"), shortcutNumber: 1, transform: { $0 },
                               subActions: children.isEmpty ? nil : children,
                               targetLanguageCode: config.defaultTranslateLanguage)
        default:
            return nil
        }
    }

    private static func translationSubActions(config: QuickActionsConfig) -> [QuickAction] {
        // Resolve localized names per construction rather than caching locale-dependent strings.
        let languages = TranslationTargetLanguage.supportedLanguages
        let defaultID = "translate_to_\(config.defaultTranslateLanguage)"
        var order = config.subActionOrder["translate"] ?? ["translate_to_es", "translate_to_de", "translate_to_fr", "translate_to_ja", "translate_to_zh"]
        if let defaultIndex = order.firstIndex(of: defaultID) {
            let candidates = ["en", "es", "de", "fr", "ja", "zh"] + languages.map(\.code)
            if let replacement = candidates.first(where: { $0 != config.defaultTranslateLanguage && !order.contains("translate_to_\($0)") }) {
                order[defaultIndex] = "translate_to_\(replacement)"
            } else {
                order.remove(at: defaultIndex)
            }
        }
        let disabled = Set(config.disabledSubActionIds["translate"] ?? [])
        let byID = Dictionary(uniqueKeysWithValues: languages.map { ("translate_to_\($0.code)", $0) })
        return order.filter { !disabled.contains($0) && $0 != defaultID }
            .compactMap { byID[$0] }.enumerated().map { index, language in
                QuickAction(id: "translate_to_\(language.code)", title: language.name, icon: .system("globe"),
                            shortcutNumber: index + 1, transform: { $0 }, targetLanguageCode: language.code)
            }
    }
}

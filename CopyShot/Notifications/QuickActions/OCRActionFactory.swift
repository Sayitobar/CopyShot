import Foundation

enum OCRActionFactory {
    static func actions(for text: String?, config: QuickActionsConfig) -> [QuickAction] {
        let isURL = text != nil && WebActionHelper.isURL(text!)
        
        // Base sub-actions pool for Change Case
        let allCaseSubActions: [String: QuickAction] = [
            "title_case": QuickAction(
                id: "title_case",
                title: "Title Case",
                icon: .typography("Aa"),
                shortcutNumber: 1,
                transform: QuickActionTransforms.toTitleCase
            ),
            "uppercase": QuickAction(
                id: "uppercase",
                title: "UPPERCASE",
                icon: .typography("AA"),
                shortcutNumber: 2,
                transform: QuickActionTransforms.toUppercase
            ),
            "lowercase": QuickAction(
                id: "lowercase",
                title: "lowercase",
                icon: .typography("aa"),
                shortcutNumber: 3,
                transform: QuickActionTransforms.toLowercase
            ),
            "toggle_case": QuickAction(
                id: "toggle_case",
                title: "tOGGLE cASE",
                icon: .typography("aA"),
                shortcutNumber: 4,
                transform: QuickActionTransforms.toToggleCase
            ),
            "sentence_case": QuickAction(
                id: "sentence_case",
                title: "Sentence case.",
                icon: .system("text.alignleft"),
                shortcutNumber: 5,
                transform: QuickActionTransforms.toSentenceCase
            )
        ]
        
        // Ordered & filtered Change Case sub-actions
        let caseOrder = config.subActionOrder["change_case"] ?? ["title_case", "uppercase", "lowercase", "toggle_case", "sentence_case"]
        let disabledCaseIds = Set(config.disabledSubActionIds["change_case"] ?? [])
        let activeCaseSubActions: [QuickAction] = caseOrder
            .filter { !disabledCaseIds.contains($0) }
            .compactMap { allCaseSubActions[$0] }
            .enumerated()
            .map { index, action in
                QuickAction(
                    id: action.id,
                    title: action.title,
                    icon: action.icon,
                    shortcutNumber: index + 1,
                    transform: action.transform
                )
            }
        
        // Translation sub-actions pool
        var allTranslateSubActions: [String: QuickAction] = [:]
        for lang in TranslationTargetLanguage.supportedLanguages {
            allTranslateSubActions["translate_to_\(lang.code)"] = QuickAction(
                id: "translate_to_\(lang.code)",
                title: lang.name,
                icon: .system("globe"),
                shortcutNumber: 1,
                transform: { $0 },
                targetLanguageCode: lang.code
            )
        }
        
        let defaultSubOrder = ["translate_to_es", "translate_to_de", "translate_to_fr", "translate_to_ja", "translate_to_zh"]
        var configuredTranslateOrder = config.subActionOrder["translate"] ?? defaultSubOrder
        
        // If configured order contains the default language, swap it with "en" or first available language not in order
        if let defaultIndex = configuredTranslateOrder.firstIndex(of: "translate_to_\(config.defaultTranslateLanguage)") {
            let candidateLangs = ["en", "es", "de", "fr", "ja", "zh"] + TranslationTargetLanguage.supportedLanguages.map(\.code)
            if let replacement = candidateLangs.first(where: { $0 != config.defaultTranslateLanguage && !configuredTranslateOrder.contains("translate_to_\($0)") }) {
                configuredTranslateOrder[defaultIndex] = "translate_to_\(replacement)"
            } else {
                configuredTranslateOrder.remove(at: defaultIndex)
            }
        }
        
        let disabledTranslateIds = Set(config.disabledSubActionIds["translate"] ?? [])
        let activeTranslateSubActions: [QuickAction] = configuredTranslateOrder
            .filter { !disabledTranslateIds.contains($0) && $0 != "translate_to_\(config.defaultTranslateLanguage)" }
            .compactMap { allTranslateSubActions[$0] }
            .enumerated()
            .map { index, action in
                QuickAction(
                    id: action.id,
                    title: action.title,
                    icon: action.icon,
                    shortcutNumber: index + 1,
                    transform: action.transform,
                    targetLanguageCode: action.targetLanguageCode
                )
            }
        
        // Map top-level actions
        var activeActions: [QuickAction] = []
        let disabledActionIds = Set(config.disabledActionIds)
        
        for actionId in config.actionOrder where !disabledActionIds.contains(actionId) {
            let nextShortcutNumber = activeActions.count + 1
            
            switch actionId {
            case "change_case":
                activeActions.append(
                    QuickAction(
                        id: "change_case",
                        title: "Change Case",
                        icon: .system("textformat"),
                        shortcutNumber: nextShortcutNumber,
                        transform: QuickActionTransforms.toTitleCase,
                        subActions: activeCaseSubActions.isEmpty ? nil : activeCaseSubActions
                    )
                )
            case "join_lines":
                activeActions.append(
                    QuickAction(
                        id: "join_lines",
                        title: "Join Lines",
                        icon: .system("text.line.2.summary"),
                        shortcutNumber: nextShortcutNumber,
                        transform: QuickActionTransforms.joinLines
                    )
                )
            case "search_web":
                activeActions.append(
                    QuickAction(
                        id: "search_web",
                        title: isURL ? "Open URL" : "Search Web",
                        icon: isURL ? .system("safari") : .system("magnifyingglass"),
                        shortcutNumber: nextShortcutNumber,
                        transform: { $0 },
                        operation: .web(payloadIndex: nil)
                    )
                )
            case "translate":
                if #available(macOS 15.0, *) {
                    activeActions.append(
                        QuickAction(
                            id: "translate",
                            title: "Translate (to \(config.defaultTranslateLanguage).)",
                            icon: .system("translate"),
                            shortcutNumber: nextShortcutNumber,
                            transform: { $0 },
                            subActions: activeTranslateSubActions.isEmpty ? nil : activeTranslateSubActions,
                            targetLanguageCode: config.defaultTranslateLanguage
                        )
                    )
                }
            default:
                break
            }
        }
        
        return activeActions
    }
}

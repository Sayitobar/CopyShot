import Foundation

struct ModeActionConfiguration: Codable, Equatable {
    var actionOrder: [String]
    var disabledActionIds: [String]
}

struct QuickActionsConfig: Codable, Equatable {
    var isEnabled = true
    var showNumericShortcuts = true
    var playHapticsOnHover = true
    var searchEngine: SearchEngine = .google
    var defaultTranslateLanguage = "en"
    var markdownUsesFirstRowAsHeader = false
    var subActionOrder: [String: [String]] = [
        "change_case": ["title_case", "uppercase", "lowercase", "toggle_case", "sentence_case"],
        "translate": ["translate_to_es", "translate_to_de", "translate_to_fr", "translate_to_ja", "translate_to_zh"]
    ]
    var disabledSubActionIds: [String: [String]] = [:]
    var modes: [String: ModeActionConfiguration] = ActionRegistry.defaultModeConfigurations

    init() {}

    func modeConfiguration(for mode: CaptureMode, registry: ActionRegistry = .shared) -> ModeActionConfiguration {
        guard let stored = modes[mode.rawValue] else { return registry.defaultConfiguration(for: mode) }
        return registry.reconcile(stored, for: mode)
    }

    mutating func setModeConfiguration(_ value: ModeActionConfiguration, for mode: CaptureMode) {
        modes[mode.rawValue] = ActionRegistry.shared.reconcile(value, for: mode)
    }

    // Source compatibility for existing OCR callers. Persistence uses only mode entries.
    var actionOrder: [String] {
        get { modeConfiguration(for: .standardOCR).actionOrder }
        set {
            var value = modeConfiguration(for: .standardOCR)
            value.actionOrder = newValue
            setModeConfiguration(value, for: .standardOCR)
        }
    }
    var disabledActionIds: [String] {
        get { modeConfiguration(for: .standardOCR).disabledActionIds }
        set {
            var value = modeConfiguration(for: .standardOCR)
            value.disabledActionIds = newValue
            setModeConfiguration(value, for: .standardOCR)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, modes, actionOrder, disabledActionIds, isEnabled
        case showNumericShortcuts, playHapticsOnHover, searchEngine, defaultTranslateLanguage
        case markdownUsesFirstRowAsHeader, subActionOrder, disabledSubActionIds
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? isEnabled
        showNumericShortcuts = try values.decodeIfPresent(Bool.self, forKey: .showNumericShortcuts) ?? showNumericShortcuts
        playHapticsOnHover = try values.decodeIfPresent(Bool.self, forKey: .playHapticsOnHover) ?? playHapticsOnHover
        searchEngine = try values.decodeIfPresent(SearchEngine.self, forKey: .searchEngine) ?? searchEngine
        defaultTranslateLanguage = try values.decodeIfPresent(String.self, forKey: .defaultTranslateLanguage) ?? defaultTranslateLanguage
        markdownUsesFirstRowAsHeader = try values.decodeIfPresent(Bool.self, forKey: .markdownUsesFirstRowAsHeader) ?? false
        subActionOrder = try values.decodeIfPresent([String: [String]].self, forKey: .subActionOrder) ?? subActionOrder
        disabledSubActionIds = try values.decodeIfPresent([String: [String]].self, forKey: .disabledSubActionIds) ?? [:]
        if let stored = try values.decodeIfPresent([String: ModeActionConfiguration].self, forKey: .modes) {
            modes.merge(stored) { _, supplied in supplied }
        } else if schemaVersion < 2 {
            let order = try values.decodeIfPresent([String].self, forKey: .actionOrder) ?? actionOrder
            let disabled = try values.decodeIfPresent([String].self, forKey: .disabledActionIds) ?? []
            modes[CaptureMode.standardOCR.rawValue] = .init(actionOrder: order, disabledActionIds: disabled)
        }
        for descriptor in CaptureModeDescriptor.available {
            setModeConfiguration(modeConfiguration(for: descriptor.id), for: descriptor.id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(2, forKey: .schemaVersion)
        try values.encode(modes, forKey: .modes)
        try values.encode(isEnabled, forKey: .isEnabled)
        try values.encode(showNumericShortcuts, forKey: .showNumericShortcuts)
        try values.encode(playHapticsOnHover, forKey: .playHapticsOnHover)
        try values.encode(searchEngine, forKey: .searchEngine)
        try values.encode(defaultTranslateLanguage, forKey: .defaultTranslateLanguage)
        try values.encode(markdownUsesFirstRowAsHeader, forKey: .markdownUsesFirstRowAsHeader)
        try values.encode(subActionOrder, forKey: .subActionOrder)
        try values.encode(disabledSubActionIds, forKey: .disabledSubActionIds)
    }
}

import Foundation

struct ActionEnvironment {
    let translationAvailable: Bool
}

struct ActionDefinition {
    let metadata: ActionMetadata
    let defaultEnabledModes: Set<CaptureMode>
    var unavailableReason: (ActionEnvironment) -> String? = { _ in nil }
    let makeAction: (ActionContext, QuickActionsConfig) -> QuickAction?
}

protocol ActionProvider {
    var definitions: [ActionDefinition] { get }
}

struct ActionCatalogEntry {
    let metadata: ActionMetadata
    let isEnabled: Bool
    let unavailableReason: String?
}

struct ActionRegistry {
    static let shared = ActionRegistry()
    let definitions: [ActionDefinition]
    let translationAvailable: Bool

    init(providers: [any ActionProvider] = [BuiltInActionProvider()], translationAvailable: Bool = {
        if #available(macOS 15.0, *) { return true }
        return false
    }()) {
        var seen = Set<String>()
        definitions = providers.flatMap(\.definitions).filter { seen.insert($0.metadata.id).inserted }
        self.translationAvailable = translationAvailable
    }

    static var defaultModeConfigurations: [String: ModeActionConfiguration] {
        Dictionary(uniqueKeysWithValues: CaptureModeDescriptor.available.map {
            ($0.id.rawValue, shared.defaultConfiguration(for: $0.id))
        })
    }

    func defaultConfiguration(for mode: CaptureMode) -> ModeActionConfiguration {
        let matching = definitions.filter { $0.metadata.supportedModes.contains(mode) }
        return .init(actionOrder: matching.map { $0.metadata.id },
                     disabledActionIds: matching.filter { !$0.defaultEnabledModes.contains(mode) }.map { $0.metadata.id })
    }

    func reconcile(_ stored: ModeActionConfiguration, for mode: CaptureMode) -> ModeActionConfiguration {
        var seen = Set<String>()
        var order = stored.actionOrder.filter { seen.insert($0).inserted }
        var disabled = Set(stored.disabledActionIds)
        for id in defaultConfiguration(for: mode).actionOrder where seen.insert(id).inserted {
            order.append(id)
            disabled.insert(id)
        }
        return .init(actionOrder: order, disabledActionIds: disabled.sorted())
    }

    func catalog(for mode: CaptureMode, config: QuickActionsConfig) -> [ActionCatalogEntry] {
        let scoped = config.modeConfiguration(for: mode, registry: self)
        let map = Dictionary(uniqueKeysWithValues: definitions.map { ($0.metadata.id, $0) })
        return scoped.actionOrder.compactMap { id in
            guard let definition = map[id], definition.metadata.supportedModes.contains(mode) else { return nil }
            return .init(metadata: definition.metadata, isEnabled: !scoped.disabledActionIds.contains(id),
                         unavailableReason: definition.unavailableReason(.init(translationAvailable: translationAvailable)))
        }
    }

    func actions(context: ActionContext, config: QuickActionsConfig) -> [QuickAction] {
        guard config.isEnabled else { return [] }
        let map = Dictionary(uniqueKeysWithValues: definitions.map { ($0.metadata.id, $0) })
        return catalog(for: context.mode, config: config)
            .filter { $0.isEnabled && $0.unavailableReason == nil }
            .compactMap { map[$0.metadata.id]?.makeAction(context, config) }
            .enumerated().map { index, action in action.numbered(index + 1) }
    }
}

extension QuickAction {
    func numbered(_ index: Int) -> Self {
        var seen = Set<String>()
        let children = subActions?.filter { seen.insert($0.id).inserted }
        return QuickAction(id: id, title: title, icon: icon, shortcutNumber: index <= 9 ? index : nil,
                    transform: transform, subActions: children?.enumerated().map { $0.element.numbered($0.offset + 1) },
                    targetLanguageCode: targetLanguageCode, operation: operation, helpText: helpText)
    }
}

struct BuiltInActionProvider: ActionProvider {
    var definitions: [ActionDefinition] {
        [
            ocr("change_case", "Change Case", "Format recognized text.", .system("textformat"), submenu: true),
            ocr("join_lines", "Join Lines", "Merge wrapped lines while preserving paragraphs.", .system("text.line.2.summary")),
            definition("search_web", "Search Web / Open URL", "Open a detected link or search its text.", .system("magnifyingglass"),
                       modes: [.standardOCR, .qrBarcode], enabled: [.standardOCR, .qrBarcode], parameters: [.searchEngine]) { context, _ in
                if case .barcodes(let codes) = context.payload, codes.count > 1 {
                    let children = codes.enumerated().map { index, code in
                        QuickAction(id: "barcode_web_\(index)", title: "\(index + 1). \(TextPreview.format(code.payload, limit: 22))",
                                    icon: .system(WebActionHelper.isURL(code.payload) ? "safari" : "magnifyingglass"),
                                    shortcutNumber: nil, operation: .web(payloadIndex: index), helpText: code.payload)
                    }
                    return QuickAction(id: "search_web", title: "Open / Search Code", icon: .system("qrcode"),
                                       shortcutNumber: nil, subActions: children, operation: .submenu)
                }
                let isURL = WebActionHelper.isURL(context.text)
                return QuickAction(id: "search_web", title: isURL ? "Open URL" : "Search Web", icon: .system(isURL ? "safari" : "magnifyingglass"),
                                   shortcutNumber: nil, operation: .web(payloadIndex: nil))
            },
            ocr("translate", "Translate", "Translate on this Mac.", .system("globe"), submenu: true, parameters: [.translateLanguage], translation: true),
            definition("copy_raw", "Copy Raw Data", "Copy every recognized barcode payload.", .system("doc.on.doc"), modes: [.qrBarcode]) { _, _ in
                QuickAction(id: "copy_raw", title: "Copy Raw Data", icon: .system("doc.on.doc"), shortcutNumber: nil, operation: .copyBarcodes)
            },
            definition("latex_wrap_dollar", "Wrap Math", "Cycle raw, inline, and display math.", .typography("$"), modes: [.latex], enabled: [.latex]) { _, _ in
                QuickAction(id: "latex_wrap_dollar", title: "Wrap Math", icon: .typography("$"), shortcutNumber: nil, transform: QuickActionTransforms.wrapDollar)
            },
            definition("search_math", "Open in Wolfram Alpha", "Open this formula in Wolfram Alpha.", .system("function"), modes: [.latex]) { _, _ in
                QuickAction(id: "search_math", title: "Open in Wolfram Alpha", icon: .system("function"), shortcutNumber: nil, operation: .wolfram)
            },
            table("table_markdown", "Copy Markdown", .markdown, enabled: true, parameters: [.markdownHeader]),
            table("table_csv", "Copy CSV", .csv, enabled: true),
            table("table_tsv", "Copy TSV", .tsv, enabled: false)
        ]
    }

    private func definition(_ id: String, _ title: String, _ description: String, _ icon: ActionIcon,
                            modes: Set<CaptureMode>, enabled: Set<CaptureMode> = [], submenu: Bool = false,
                            parameters: [ActionParameter] = [], translation: Bool = false,
                            make: @escaping (ActionContext, QuickActionsConfig) -> QuickAction?) -> ActionDefinition {
        .init(metadata: .init(id: id, title: title, description: description, icon: icon,
                             hasSubActions: submenu, hasParameters: !parameters.isEmpty, supportedModes: modes, parameters: parameters),
              defaultEnabledModes: enabled,
              unavailableReason: { environment in translation && !environment.translationAvailable ? "Requires macOS 15 or later" : nil },
              makeAction: make)
    }

    private func ocr(_ id: String, _ title: String, _ description: String, _ icon: ActionIcon,
                     submenu: Bool = false, parameters: [ActionParameter] = [], translation: Bool = false) -> ActionDefinition {
        definition(id, title, description, icon, modes: [.standardOCR], enabled: [.standardOCR], submenu: submenu,
                   parameters: parameters, translation: translation) { context, config in
            var isolated = config
            isolated.actionOrder = [id]
            isolated.disabledActionIds = isolated.actionOrder.filter { $0 != id }
            return OCRActionFactory.actions(for: context.text, config: isolated).first { $0.id == id }
        }
    }

    private func table(_ id: String, _ title: String, _ format: TableExportFormat, enabled: Bool,
                       parameters: [ActionParameter] = []) -> ActionDefinition {
        definition(id, title, "Export recognized table cells.", .system("tablecells"), modes: [.table],
                   enabled: enabled ? [.table] : [], parameters: parameters) { _, _ in
            QuickAction(id: id, title: title, icon: .system("tablecells"), shortcutNumber: nil, operation: .table(format))
        }
    }
}

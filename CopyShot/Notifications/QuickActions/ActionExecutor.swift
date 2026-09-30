import Foundation

enum ActionResult {
    case copy(ActionContext, subtitle: String)
    case openURL(URL)
}

@MainActor
protocol ActionExecuting {
    func execute(_ action: QuickAction, context: ActionContext, config: QuickActionsConfig) async throws -> ActionResult
}

enum ActionExecutionError: LocalizedError {
    case incompatiblePayload, invalidURL, submenuOnly
    var errorDescription: String? {
        switch self {
        case .incompatiblePayload: "This action is unavailable for this capture."
        case .invalidURL: "Could not construct a valid URL."
        case .submenuOnly: "Choose an item from the submenu."
        }
    }
}

@MainActor
struct BuiltInActionExecutor: ActionExecuting {
    var translate: (String, String) async throws -> TranslationResult = { text, language in
        try await withCheckedThrowingContinuation { continuation in
            TranslationService.shared.translate(text: text, targetLanguageCode: language) {
                continuation.resume(with: $0)
            }
        }
    }

    func execute(_ action: QuickAction, context: ActionContext, config: QuickActionsConfig) async throws -> ActionResult {
        try Task.checkCancellation()
        switch action.operation {
        case .transform:
            return .copy(context.replacingText(action.transform(context.text)), subtitle: "Processed text:")
        case .translate(let language):
            let result = try await translate(context.text, language)
            try Task.checkCancellation()
            return .copy(context.replacingText(result.translatedText), subtitle: "\(result.sourceLanguageName) → \(result.targetLanguageName)")
        case .web(let index):
            let text: String
            if let index {
                guard case .barcodes(let codes) = context.payload, codes.indices.contains(index) else { throw ActionExecutionError.incompatiblePayload }
                text = codes[index].payload
            } else { text = context.text }
            guard let url = WebActionHelper.detectURL(in: text) ?? config.searchEngine.searchURL(for: text) else { throw ActionExecutionError.invalidURL }
            return .openURL(url)
        case .copyBarcodes:
            guard case .barcodes(let codes) = context.payload else { throw ActionExecutionError.incompatiblePayload }
            return .copy(context.replacingText(codes.map(\.payload).joined(separator: "\n")), subtitle: "Raw data:")
        case .wolfram:
            guard case .latex(let formula, _) = context.payload else { throw ActionExecutionError.incompatiblePayload }
            let trimmed = formula.trimmingCharacters(in: .whitespacesAndNewlines)
            let raw: String
            if trimmed.count >= 4 && trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") {
                raw = String(trimmed.dropFirst(2).dropLast(2))
            } else if trimmed.count >= 2 && trimmed.hasPrefix("$") && trimmed.hasSuffix("$")
                        && !trimmed.hasPrefix("$$") && !trimmed.hasSuffix("$$") {
                raw = String(trimmed.dropFirst().dropLast())
            } else { raw = formula }
            var components = URLComponents(string: "https://www.wolframalpha.com/input")!
            components.queryItems = [.init(name: "i", value: raw)]
            guard let url = components.url else { throw ActionExecutionError.invalidURL }
            return .openURL(url)
        case .table(let format):
            guard case .table(let table) = context.payload else { throw ActionExecutionError.incompatiblePayload }
            let text: String
            switch format {
            case .markdown: text = TableExporter.markdown(table, usesFirstRowAsHeader: config.markdownUsesFirstRowAsHeader)
            case .csv: text = TableExporter.csv(table)
            case .tsv: text = TableExporter.tsv(table)
            }
            return .copy(context.replacingText(text), subtitle: "Exported table:")
        case .submenu: throw ActionExecutionError.submenuOnly
        }
    }
}

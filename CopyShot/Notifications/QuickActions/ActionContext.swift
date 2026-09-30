import Foundation

struct ActionContext: Equatable {
    let sessionID: UUID
    var payload: CaptureResult
    var text: String

    init(sessionID: UUID = UUID(), payload: CaptureResult, text: String? = nil) {
        self.sessionID = sessionID
        self.payload = payload
        self.text = text ?? payload.actionText
    }

    // Compatibility for text-only callers. Real captures always supply structured payloads.
    init(text: String, mode: CaptureMode) {
        switch mode {
        case .standardOCR: self.init(payload: .standardText(text))
        case .qrBarcode: self.init(payload: .barcodes([.init(payload: text, symbology: "")]))
        case .latex: self.init(payload: .latex(formula: text))
        case .table: self.init(payload: .table(.init(rows: [])), text: text)
        }
    }

    var mode: CaptureMode { payload.mode }

    func replacingText(_ text: String) -> Self {
        var next = self
        next.text = text
        switch payload {
        case .standardText: next.payload = .standardText(text)
        case .latex(_, let note): next.payload = .latex(formula: text, statusNote: note)
        case .table, .barcodes: break // Exported text never replaces canonical structure.
        }
        return next
    }
}

extension CaptureResult {
    var mode: CaptureMode {
        switch self {
        case .standardText: .standardOCR
        case .barcodes: .qrBarcode
        case .latex: .latex
        case .table: .table
        }
    }

    var actionText: String {
        switch self {
        case .standardText(let text): text
        case .barcodes(let codes): codes.map(\.payload).joined(separator: "\n")
        case .latex(let formula, _): formula
        case .table(let table): table.tabSeparatedText
        }
    }
}

enum TableExportFormat: Equatable { case markdown, csv, tsv }
enum ActionOperation: Equatable {
    case transform
    case translate(String)
    case web(payloadIndex: Int?)
    case copyBarcodes
    case wolfram
    case table(TableExportFormat)
    case submenu
}

enum ActionParameter: Equatable { case searchEngine, translateLanguage, markdownHeader }

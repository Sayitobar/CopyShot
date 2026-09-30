import XCTest
@testable import CopyShot

@MainActor
final class ActionExecutionTests: XCTestCase {
    @MainActor
    func testWolframPreservesMismatchedMathDelimiters() async throws {
        for formula in ["$$x$", "$x$$"] {
            let context = ActionContext(payload: .latex(formula: formula))
            let action = QuickAction(id: "search_math", title: "Wolfram", icon: .system("function"), shortcutNumber: nil, operation: .wolfram)
            let result = try await BuiltInActionExecutor().execute(action, context: context, config: .init())
            guard case .openURL(let url) = result else { return XCTFail("Expected URL") }
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, formula)
        }
    }

    func testTableExportsEscapeCellsAndRetainCanonicalRows() async throws {
        let rows = [["a,b", "quote\"", "pipe|\\"], ["line\r\nbreak", "tab\tcell"], ["ä", "", ""]]
        let context = ActionContext(payload: .table(.init(rows: rows)))
        let executor = BuiltInActionExecutor()
        let csv = try await executor.execute(QuickAction(id: "csv", title: "CSV", icon: .system("tablecells"), shortcutNumber: nil, operation: .table(.csv)), context: context, config: .init())
        guard case .copy(let exported, _) = csv else { return XCTFail("Expected copied table") }
        XCTAssertEqual(exported.payload, context.payload)
        XCTAssertEqual(exported.text, "\"a,b\",\"quote\"\"\",pipe|\\\r\n\"line\r\nbreak\",tab\tcell,\r\nä,,")
        XCTAssertEqual(TableExporter.tsv(.init(rows: rows)), "a,b\t\"quote\"\"\"\tpipe|\\\n\"line\r\nbreak\"\t\"tab\tcell\"\t\nä\t\t")
        XCTAssertEqual(TableExporter.markdown(.init(rows: [["a|b", "c\\d"], ["x\ny"]]), usesFirstRowAsHeader: false), "|  |  |\n| --- | --- |\n| a\\|b | c\\\\d |\n| x<br>y |  |")
        XCTAssertEqual(TableExporter.markdown(.init(rows: [["A", "B"], ["1", "2"]]), usesFirstRowAsHeader: true), "| A | B |\n| --- | --- |\n| 1 | 2 |")
        XCTAssertEqual(TableExporter.csv(.init(rows: [])), "")
        XCTAssertEqual(TableExporter.markdown(.init(rows: [[]]), usesFirstRowAsHeader: false), "")
    }

    func testMultipleBarcodesHaveIndividualCommandsAndOnlyNineShortcuts() async throws {
        let codes = (0..<12).map { DetectedBarcode(payload: "https://example.com/\($0)?a=1&b=2", symbology: "QR") }
        let context = ActionContext(payload: .barcodes(codes))
        let actions = ActionRegistry.shared.actions(context: context, config: .init())
        let parent = try XCTUnwrap(actions.first)
        XCTAssertEqual(parent.operation, .submenu)
        let children = try XCTUnwrap(parent.subActions)
        XCTAssertEqual(children.count, 12)
        XCTAssertEqual(children.prefix(9).map(\.shortcutNumber), (1...9).map { Optional($0) })
        XCTAssertNil(children[9].shortcutNumber)
        XCTAssertEqual(children[10].helpText, codes[10].payload)
        let result = try await BuiltInActionExecutor().execute(children[10], context: context, config: .init())
        guard case .openURL(let url) = result else { return XCTFail("Expected navigation") }
        XCTAssertEqual(url.absoluteString, codes[10].payload)
        let copy = QuickAction(id: "copy", title: "Copy", icon: .system("doc"), shortcutNumber: nil, operation: .copyBarcodes)
        guard case .copy(let copied, _) = try await BuiltInActionExecutor().execute(copy, context: context, config: .init()) else { return XCTFail("Expected copied data") }
        XCTAssertEqual(copied.text, codes.map(\.payload).joined(separator: "\n"))
    }

    func testLaTeXCycleAndWolframEncoding() async throws {
        let raw = #"\frac{x + y}{2} & z"#
        let executor = BuiltInActionExecutor()
        var context = ActionContext(payload: .latex(formula: raw))
        let wrap = try XCTUnwrap(ActionRegistry.shared.actions(context: context, config: .init()).first)
        for expected in ["$\(raw)$", "$$\(raw)$$", raw] {
            guard case .copy(let next, _) = try await executor.execute(wrap, context: context, config: .init()) else { return XCTFail("Expected wrapping") }
            context = next
            XCTAssertEqual(context.text, expected)
            XCTAssertEqual(context.payload, .latex(formula: expected))
        }
        let action = QuickAction(id: "math", title: "Math", icon: .system("function"), shortcutNumber: nil, operation: .wolfram)
        guard case .openURL(let url) = try await executor.execute(action, context: .init(payload: .latex(formula: "$$\(raw)$$")), config: .init()) else { return XCTFail("Expected Wolfram") }
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, raw)
    }
}

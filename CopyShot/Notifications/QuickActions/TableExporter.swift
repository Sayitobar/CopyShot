import Foundation

enum TableExporter {
    private static func rectangularRows(_ table: CapturedTable) -> [[String]] {
        let width = table.rows.map(\.count).max() ?? 0
        guard width > 0 else { return [] }
        return table.rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    private static func delimited(_ table: CapturedTable, delimiter: String, rowSeparator: String) -> String {
        rectangularRows(table).map { row in
            row.map { cell in
                let hasLineBreak = cell.unicodeScalars.contains { $0.value == 10 || $0.value == 13 }
                guard cell.contains(delimiter) || cell.contains("\"") || hasLineBreak else { return cell }
                return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }.joined(separator: delimiter)
        }.joined(separator: rowSeparator)
    }

    static func csv(_ table: CapturedTable) -> String { delimited(table, delimiter: ",", rowSeparator: "\r\n") }
    static func tsv(_ table: CapturedTable) -> String { delimited(table, delimiter: "\t", rowSeparator: "\n") }

    static func markdown(_ table: CapturedTable, usesFirstRowAsHeader: Bool) -> String {
        let rows = rectangularRows(table)
        guard let first = rows.first else { return "" }
        func render(_ row: [String]) -> String {
            "| " + row.map {
                $0.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "|", with: "\\|")
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .replacingOccurrences(of: "\n", with: "<br>")
            }.joined(separator: " | ") + " |"
        }
        let header = usesFirstRowAsHeader ? first : Array(repeating: "", count: first.count)
        let separator = "| " + Array(repeating: "---", count: first.count).joined(separator: " | ") + " |"
        let body = usesFirstRowAsHeader ? Array(rows.dropFirst()) : rows
        return ([render(header), separator] + body.map(render)).joined(separator: "\n")
    }
}

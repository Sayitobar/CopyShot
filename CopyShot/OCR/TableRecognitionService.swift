import AppKit

enum TableRecognitionService {
    static func recognize(_ image: CGImage, completion: @escaping (Result<CapturedTable, Error>) -> Void) {
        OCRService.performOCRSegments(on: image) { result in
            completion(result.map(cluster))
        }
    }

    static func cluster(_ segments: [OCRService.TextSegment]) -> CapturedTable {
        guard !segments.isEmpty else { return CapturedTable(rows: []) }
        struct Row {
            var centerY: CGFloat
            var height: CGFloat
            var cells: [OCRService.TextSegment]
        }
        var rows: [Row] = []
        for segment in segments.sorted(by: { $0.bounds.midY > $1.bounds.midY }) {
            if let index = rows.indices.min(by: {
                abs(rows[$0].centerY - segment.bounds.midY) < abs(rows[$1].centerY - segment.bounds.midY)
            }), abs(rows[index].centerY - segment.bounds.midY) <= min(rows[index].height, segment.bounds.height) * 0.6 {
                rows[index].cells.append(segment)
                rows[index].centerY = rows[index].cells.map(\.bounds.midY).reduce(0, +) / CGFloat(rows[index].cells.count)
            } else {
                rows.append(Row(centerY: segment.bounds.midY, height: segment.bounds.height, cells: [segment]))
            }
        }

        struct Column {
            var centerX: CGFloat
            var width: CGFloat
            var count: Int
        }
        func matchesColumn(_ column: Column, _ segment: OCRService.TextSegment) -> Bool {
            let columnMin = column.centerX - column.width / 2
            let columnMax = column.centerX + column.width / 2
            let overlap = max(0, min(columnMax, segment.bounds.maxX) - max(columnMin, segment.bounds.minX))
            return overlap >= min(column.width, segment.bounds.width) * 0.5 &&
                abs(column.centerX - segment.bounds.midX) <= max(column.width, segment.bounds.width) * 0.5
        }
        var columns: [Column] = []
        for segment in segments.sorted(by: { $0.bounds.midX < $1.bounds.midX }) {
            if let index = columns.indices.min(by: {
                abs(columns[$0].centerX - segment.bounds.midX) < abs(columns[$1].centerX - segment.bounds.midX)
            }), matchesColumn(columns[index], segment) {
                columns[index].centerX = (columns[index].centerX * CGFloat(columns[index].count) + segment.bounds.midX) / CGFloat(columns[index].count + 1)
                columns[index].width = max(columns[index].width, segment.bounds.width)
                columns[index].count += 1
            } else {
                columns.append(Column(centerX: segment.bounds.midX, width: segment.bounds.width, count: 1))
            }
        }
        columns.sort { $0.centerX < $1.centerX }
        rows.sort { $0.centerY > $1.centerY }
        return CapturedTable(rows: rows.map { row in
            var cells = Array(repeating: "", count: columns.count)
            for segment in row.cells.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
                guard let index = columns.indices.min(by: {
                    abs(columns[$0].centerX - segment.bounds.midX) < abs(columns[$1].centerX - segment.bounds.midX)
                }) else { continue }
                cells[index] = cells[index].isEmpty ? segment.text : cells[index] + " " + segment.text
            }
            return cells
        })
    }
}

import Foundation
import Testing
@testable import CopyShot

@Suite("Table clustering")
struct TableCaptureTests {
    @Test("OCR segments become ordered rows and aligned columns")
    func clustersCells() {
        let segments: [OCRService.TextSegment] = [
            .init(text: "B2", bounds: CGRect(x: 0.52, y: 0.22, width: 0.2, height: 0.1)),
            .init(text: "A1", bounds: CGRect(x: 0.10, y: 0.72, width: 0.2, height: 0.1)),
            .init(text: "A2", bounds: CGRect(x: 0.10, y: 0.22, width: 0.2, height: 0.1)),
            .init(text: "B1", bounds: CGRect(x: 0.52, y: 0.72, width: 0.2, height: 0.1))
        ]
        let table = TableRecognitionService.cluster(segments)
        #expect(table.rows == [["A1", "B1"], ["A2", "B2"]])
        #expect(table.tabSeparatedText == "A1\tB1\nA2\tB2")
    }

    @Test("Adjacent wide and narrow cells stay in separate columns")
    func keepsAdjacentColumnsSeparate() {
        let segments: [OCRService.TextSegment] = [
            .init(text: "Description", bounds: CGRect(x: 0.10, y: 0.72, width: 0.50, height: 0.1)),
            .init(text: "12", bounds: CGRect(x: 0.60, y: 0.72, width: 0.08, height: 0.1)),
            .init(text: "Another item", bounds: CGRect(x: 0.10, y: 0.22, width: 0.50, height: 0.1)),
            .init(text: "34", bounds: CGRect(x: 0.60, y: 0.22, width: 0.08, height: 0.1))
        ]
        #expect(TableRecognitionService.cluster(segments).rows == [
            ["Description", "12"], ["Another item", "34"]
        ])
    }
}

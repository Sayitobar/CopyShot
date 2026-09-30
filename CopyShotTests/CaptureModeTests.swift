import Foundation
import Testing
@testable import CopyShot

@Suite("Radial capture modes")
@MainActor
struct CaptureModeTests {
    @Test("Every sector maps to the corresponding descriptor for changing mode counts")
    func dynamicSectors() {
        for count in [3, 4, 5, 6, 8] {
            for index in 0..<count {
                let angle = -.pi / 2 + Double(index) * 2 * .pi / Double(count)
                let point = CGPoint(x: cos(angle) * 80, y: sin(angle) * 80)
                #expect(RadialModeSelection.index(for: point, modeCount: count) == index)
            }
        }
    }

    @Test("The deadzone clears a candidate and release retains the previous mode")
    func deadzone() {
        #expect(RadialModeSelection.index(for: .zero, modeCount: 4) == nil)
        #expect(RadialModeSelection.index(for: CGPoint(x: 20, y: 0), modeCount: 4) == nil)
        #expect(RadialModeSelection.index(for: CGPoint(x: 35, y: 0), modeCount: 4) != nil)

        let interaction = CaptureModeInteraction()
        interaction.begin(at: .zero)
        interaction.move(to: CGPoint(x: 80, y: 0))
        #expect(interaction.candidateIndex == 1)
        interaction.end(at: .zero)
        #expect(interaction.selectedMode == .standardOCR)
        #expect(interaction.pressPoint == nil)
    }

    @Test("Releasing in a sector commits its descriptor")
    func commit() {
        let interaction = CaptureModeInteraction()
        interaction.begin(at: .zero)
        interaction.end(at: CGPoint(x: 80, y: 0))
        #expect(interaction.selectedMode == CaptureModeDescriptor.available[1].id)
    }

    @Test("A mode picked on one display applies to another display")
    func sharesAcrossDisplays() {
        let selection = CaptureModeSelection()
        let first = CaptureModeInteraction(selection: selection)
        let second = CaptureModeInteraction(selection: selection)
        first.begin(at: .zero)
        first.end(at: CGPoint(x: 80, y: 0))
        #expect(second.selectedMode == .qrBarcode)
    }

    @Test("All sectors remain reachable at a display edge and release at the press point cancels")
    func edgeInteraction() {
        let canvas = CGSize(width: 1_000, height: 800)
        let press = CGPoint(x: 500, y: 5)
        let targets: [(CGPoint, Int)] = [
            (CGPoint(x: 550, y: 5), 0),
            (CGPoint(x: 620, y: 70), 1),
            (CGPoint(x: 500, y: 190), 2),
            (CGPoint(x: 380, y: 70), 3)
        ]
        for (point, index) in targets {
            let interaction = CaptureModeInteraction()
            interaction.begin(at: press, in: canvas)
            #expect(interaction.menuCenter == CGPoint(x: 500, y: 92))
            interaction.move(to: point)
            #expect(interaction.candidateIndex == index)
            interaction.end(at: press)
            #expect(interaction.selectedMode == .standardOCR)
        }
    }
}

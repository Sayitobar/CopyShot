import SwiftUI

/// One glyph and timing for expand/collapse controls in Settings and the HUD.
struct DisclosureChevron: View {
    let isExpanded: Bool
    static let animation = Animation.easeInOut(duration: 0.2)

    var body: some View {
        Image(systemName: "chevron.down")
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .animation(Self.animation, value: isExpanded)
            .accessibilityHidden(true)
    }
}

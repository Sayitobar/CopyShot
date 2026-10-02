import SwiftUI

/// Reusable segmented capture mode switcher with sliding selection highlight.
struct ModeSwitcher: View {
    @Binding var selectedMode: CaptureMode
    var accessibilityPrefix: String = "qa"
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(CaptureModeDescriptor.available) { descriptor in
                Button {
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)) {
                        selectedMode = descriptor.id
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: descriptor.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selectedMode == descriptor.id ? Color.accentColor : .secondary)
                        Text(descriptor.id == .qrBarcode ? "QR / Barcode" : descriptor.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(selectedMode == descriptor.id ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(accessibilityPrefix)-mode-\(descriptor.id.rawValue)")
                .accessibilityAddTraits(selectedMode == descriptor.id ? .isSelected : [])
            }
        }
        .padding(4)
        .background(alignment: .leading) {
            GeometryReader { geo in
                let count = CGFloat(CaptureModeDescriptor.available.count)
                let spacing: CGFloat = 4
                let totalPadding: CGFloat = 8
                let totalSpacing = spacing * (count - 1)
                let itemWidth = (geo.size.width - totalPadding - totalSpacing) / count
                let index = CGFloat(CaptureModeDescriptor.available.firstIndex(where: { $0.id == selectedMode }) ?? 0)
                
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: max(0, itemWidth), height: max(0, geo.size.height - totalPadding))
                    .offset(x: 4 + index * (itemWidth + spacing), y: 4)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(accessibilityPrefix)-mode-switcher")
    }
}

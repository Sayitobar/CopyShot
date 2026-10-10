import SwiftUI

struct InspectionImageView: View {
    let image: CGImage
    var regions: [OCRInspection.Region] = []
    @Binding var selectedRegion: Int?
    var revealRequest = 0
    @State private var zoom: CGFloat = 1
    @State private var actualSize = false
    @Environment(\.displayScale) private var displayScale

    private var imageSize: CGSize { CGSize(width: image.width, height: image.height) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Fit") { actualSize = false; zoom = 1 }
                    .accessibilityIdentifier("inspection-fit")
                Button("Actual Size") {
                    actualSize = true
                    zoom = 1
                }
                Spacer()
                Button { zoom = max(0.25, zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help("Zoom out").accessibilityLabel("Zoom out")
                Text(actualSize ? String(format: "%.0f%% pixels", Double(zoom) * 100) : String(format: "Fit ×%.2g", Double(zoom)))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspection-zoom-label")
                Button { zoom = min(16, zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help("Zoom in").accessibilityLabel("Zoom in")
                    .accessibilityIdentifier("inspection-zoom-in")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .medium))
            .padding(12)
            Divider()
            GeometryReader { geometry in
                let rect = InspectionGeometry.imageRect(imageSize: imageSize, viewport: geometry.size, zoom: zoom,
                                                        actualSize: actualSize, displayScale: displayScale)
                InspectionViewport(image: image, regions: regions, selectedRegion: $selectedRegion,
                                   revealRequest: revealRequest, imageRect: rect,
                                   canvasSize: CGSize(width: max(geometry.size.width, rect.maxX),
                                                      height: max(geometry.size.height, rect.maxY)))
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }
}

/// The scroll document and selection reveal share the same explicit image coordinates.
private struct InspectionViewport: NSViewRepresentable {
    let image: CGImage
    let regions: [OCRInspection.Region]
    @Binding var selectedRegion: Int?
    let revealRequest: Int
    let imageRect: CGRect
    let canvasSize: CGSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> InspectionScrollView {
        let scroll = InspectionScrollView()
        scroll.setAccessibilityIdentifier("inspection-image-viewport")
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        let document = InspectionDocument(rootView: canvas)
        document.isFlipped = true
        document.sizingOptions = []
        scroll.documentView = document
        scroll.didLayout = { [weak coordinator = context.coordinator] scroll in
            coordinator?.revealIfNeeded(in: scroll)
        }
        return scroll
    }

    func updateNSView(_ scroll: InspectionScrollView, context: Context) {
        guard let document = scroll.documentView as? InspectionDocument else { return }
        document.rootView = canvas
        document.setFrameSize(canvasSize)
        let coordinator = context.coordinator
        if !coordinator.initialized || coordinator.selectedRegion != selectedRegion ||
            coordinator.revealRequest != revealRequest {
            coordinator.needsReveal = true
        }
        coordinator.initialized = true
        coordinator.selectedRegion = selectedRegion
        coordinator.revealRequest = revealRequest
        coordinator.regionRect = regions.first(where: { $0.id == selectedRegion }).map {
            InspectionGeometry.regionRect($0.bounds, imageRect: imageRect)
        }
        scroll.layoutSubtreeIfNeeded()
        coordinator.revealIfNeeded(in: scroll)
    }

    private var canvas: InspectionCanvas {
        InspectionCanvas(image: image, regions: regions, selectedRegion: $selectedRegion,
                         imageRect: imageRect, canvasSize: canvasSize)
    }

    final class Coordinator {
        var initialized = false
        var selectedRegion: Int?
        var revealRequest = 0
        var regionRect: CGRect?
        var needsReveal = false

        func revealIfNeeded(in scroll: NSScrollView) {
            guard needsReveal, let rect = regionRect, let document = scroll.documentView else { return }
            let clip = scroll.contentView
            guard clip.bounds.width > 0, clip.bounds.height > 0 else { return }
            needsReveal = false
            clip.scroll(to: InspectionGeometry.revealOrigin(regionRect: rect,
                                                            canvasSize: document.frame.size,
                                                            viewport: clip.bounds.size))
            scroll.reflectScrolledClipView(clip)
        }
    }
}

private final class InspectionScrollView: NSScrollView {
    var didLayout: ((NSScrollView) -> Void)?
    override func layout() {
        super.layout()
        didLayout?(self)
    }
}

private typealias InspectionDocument = NSHostingView<InspectionCanvas>

private struct InspectionCanvas: View {
    let image: CGImage
    let regions: [OCRInspection.Region]
    @Binding var selectedRegion: Int?
    let imageRect: CGRect
    let canvasSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable().interpolation(.high)
                .frame(width: imageRect.width, height: imageRect.height)
                .offset(x: imageRect.minX, y: imageRect.minY)
            ForEach(regions) { region in
                let bounds = InspectionGeometry.regionRect(region.bounds, imageRect: imageRect)
                Button { selectedRegion = region.id } label: {
                    Rectangle()
                        .fill(Color.accentColor.opacity(selectedRegion == region.id ? 0.22 : 0.05))
                        .overlay(Rectangle().strokeBorder(Color.accentColor,
                                                         lineWidth: selectedRegion == region.id ? 2 : 1))
                        .overlay(alignment: .topLeading) {
                            Text("\(region.id)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .foregroundStyle(.white).background(Color.accentColor)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Region \(region.id): \(region.text)")
                .accessibilityIdentifier("inspection-box-\(region.id)")
                .accessibilityValue(selectedRegion == region.id ? "Selected" : "Not selected")
                .accessibilityAddTraits(selectedRegion == region.id ? .isSelected : [])
                .frame(width: bounds.width, height: bounds.height)
                .offset(x: bounds.minX, y: bounds.minY)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}

import SwiftUI

private enum InspectionStage: String, Identifiable {
    case original, monochrome, input, locations, assembled, transformed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original capture"
        case .monochrome: "Monochrome"
        case .input: "OCR input"
        case .locations: "Text locations"
        case .assembled: "Assembled text"
        case .transformed: "Transformed text"
        }
    }
}

struct OCRInspectionView: View {
    let record: OCRInspection
    let currentText: String
    let close: () -> Void
    let measureChrome: (CGFloat) -> Void
    @ObservedObject var settings: SettingsManager
    @State private var stage: InspectionStage = .locations
    @State private var selectedRegion: Int?
    @State private var revealRequest = 0
    @State private var monochrome: CGImage?
    @State private var isRenderingPreview = true
    @State private var showProcessedLocations = false

    private var stages: [InspectionStage] {
        var stages: [InspectionStage] = [.original]
        if record.preprocessing == .applied { stages.append(.monochrome) }
        stages += [.input, .locations]
        if record.errorDescription == nil {
            stages.append(.assembled)
            if currentText != record.assembledText { stages.append(.transformed) }
        }
        return stages
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider()
                flow
                Divider()
            }
            .background(.regularMaterial)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: InspectionChromeHeightKey.self, value: proxy.size.height)
            })
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(stage.title).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if stage == .locations {
                            Picker("Image", selection: $showProcessedLocations) {
                                Text("Original").tag(false)
                                Text("OCR input").tag(true)
                            }
                            .pickerStyle(.segmented).fixedSize()
                        }
                    }
                    .padding(16)
                    Divider()
                    stageContent
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                details.frame(minWidth: 250, idealWidth: 290, maxWidth: 370)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(settings.appearance.colorScheme)
        .onPreferenceChange(InspectionChromeHeightKey.self, perform: measureChrome)
        .task(id: record.id) {
            guard record.preprocessing == .applied else { isRenderingPreview = false; return }
            let original = record.original
            let preview = await Task.detached(priority: .utility) {
                OCRPreprocessor.monochromePreview(original)
            }.value
            guard !Task.isCancelled else { return }
            monochrome = preview
            isRenderingPreview = false
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            InspectionCloseButton(close: close)
            Image(systemName: "viewfinder").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Capture Inspection").font(.system(size: 15, weight: .semibold))
                Text("See how this capture became text.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Label("On-device", systemImage: "lock.shield")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var flow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    ForEach(stages) { item in
                        stageCard(item).id(item)
                        if item != stages.last { connection(after: item) }
                    }
                }
                .padding(20)
            }
            .onChange(of: stage) { _, value in
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }

    private func stageCard(_ item: InspectionStage) -> some View {
        Button { stage = item } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    if let image = image(for: item) {
                        Image(decorative: image, scale: 1).resizable().scaledToFit().padding(8)
                        if item == .locations {
                            GeometryReader { proxy in
                                let area = InspectionGeometry.imageRect(imageSize: CGSize(width: image.width, height: image.height),
                                                                        viewport: proxy.size, zoom: 1)
                                ForEach(record.regions) { region in
                                    let rect = InspectionGeometry.regionRect(region.bounds, imageRect: area)
                                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 1)
                                        .frame(width: rect.width, height: rect.height)
                                        .offset(x: rect.minX, y: rect.minY)
                                }
                            }.padding(8)
                        }
                    } else if item == .monochrome {
                        if isRenderingPreview { ProgressView().controlSize(.small) }
                        else { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                    } else {
                        Text(item == .transformed ? currentText : record.assembledText)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(4).frame(maxWidth: .infinity, alignment: .topLeading).padding(10)
                    }
                }
                .frame(width: 136, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Text(item.title).font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                    if stage == item { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                .frame(width: 136)
            }
            .padding(10)
            .background(stage == item ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(stage == item ? Color.accentColor : .secondary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("inspection-stage-\(item.rawValue)")
    }

    private func connection(after item: InspectionStage) -> some View {
        VStack(spacing: 8) {
            Text(connectionDescription(after: item))
                .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "arrow.right").font(.system(size: 17, weight: .light)).foregroundStyle(.tertiary)
        }
        .frame(width: 100)
    }

    private func connectionDescription(after item: InspectionStage) -> String {
        switch item {
        case .original: record.preprocessing == .applied ? "Convert to monochrome" : "Use original; preprocessing unavailable"
        case .monochrome: "Increase contrast ×1.5"
        case .input: "Recognize text with Apple Vision"
        case .locations: "Arrange regions into reading order"
        case .assembled: "Apply text transformation"
        case .transformed: ""
        }
    }

    private func image(for stage: InspectionStage) -> CGImage? {
        switch stage {
        case .original: record.original
        case .monochrome: monochrome
        case .input: record.input
        case .locations: showProcessedLocations ? record.input : record.original
        case .assembled, .transformed: nil
        }
    }

    @ViewBuilder private var stageContent: some View {
        if let image = image(for: stage) {
            InspectionImageView(image: image, regions: stage == .locations ? record.regions : [],
                                selectedRegion: $selectedRegion, revealRequest: revealRequest)
        } else if stage == .monochrome {
            VStack(spacing: 12) {
                if isRenderingPreview { ProgressView("Rendering monochrome preview…") }
                else { Text("Monochrome preview unavailable. The exact OCR input is still available.").foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                Text((stage == .transformed ? currentText : record.assembledText).isEmpty ? "No text recognized" :
                        (stage == .transformed ? currentText : record.assembledText))
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(20)
                    .accessibilityIdentifier("inspection-output")
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var details: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("THIS CAPTURE").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        detail("Engine", "Apple Vision OCR")
                        detail("Image", "\(record.original.width) × \(record.original.height) px")
                        detail("Recognition", record.configuration.level == RecognitionLevel.accurate.rawValue ? "Accurate" : "Fast")
                        detail("Languages", record.configuration.languages.joined(separator: ", "))
                        detail("Language correction", record.configuration.usesLanguageCorrection ? "Enabled" : "Disabled")
                        Text(record.preprocessing.explanation).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROCESSING TIME").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        detail("Preprocessing", milliseconds(record.timings.preprocessing))
                        detail("Recognition", milliseconds(record.timings.recognition))
                        detail("Text assembly", milliseconds(record.timings.assembly))
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RECOGNIZED REGIONS · \(record.regions.count)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        if let error = record.errorDescription {
                            Label("Recognition failed", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                            Text(error).font(.system(size: 12)).textSelection(.enabled)
                        } else if record.regions.isEmpty {
                            Text("No text regions recognized").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        ForEach(record.regions) { region in
                            Button {
                                selectedRegion = region.id
                                stage = .locations
                                revealRequest += 1
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(region.id)").font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(region.text).font(.system(size: 12))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(String(format: "Engine confidence: %.2f", region.confidence))
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if selectedRegion == region.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(Color.accentColor.opacity(selectedRegion == region.id ? 0.12 : 0))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain).id(region.id)
                            .accessibilityIdentifier("inspection-region-\(region.id)")
                            .accessibilityValue(selectedRegion == region.id ? "Selected" : "Not selected")
                            .accessibilityAddTraits(selectedRegion == region.id ? .isSelected : [])
                        }
                    }
                }
                .padding(18)
            }
            .onChange(of: selectedRegion) { _, id in
                if let id { withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value.isEmpty ? "Engine default" : value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
    }

    private func milliseconds(_ value: Double) -> String { String(format: "%.1f ms", value) }
}

private struct InspectionChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct InspectionCloseButton: View {
    let close: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: close) {
            Circle().fill(hovered ? Color.red : Color.secondary.opacity(0.3))
                .frame(width: 12, height: 12)
                .overlay {
                    if hovered { Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.black.opacity(0.6)) }
                }
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .help("Close inspection").accessibilityLabel("Close inspection")
        .accessibilityIdentifier("inspection-close")
        .keyboardShortcut("w", modifiers: .command)
    }
}

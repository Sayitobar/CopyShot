//
//  CaptureView.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI

struct CaptureView: View {
    @ObservedObject var modeInteraction: CaptureModeInteraction
    @ObservedObject private var modeSelection: CaptureModeSelection
    @State private var startPoint: CGPoint?
    @State private var endPoint: CGPoint?
    @State private var mouseLocation: CGPoint = .zero
    @State private var isMouseInside: Bool
    @State private var modeLabelSize: CGSize = .zero
    let onCapture: (CGRect, NSScreen, CaptureMode) -> Void
    let screen: NSScreen

    init(onCapture: @escaping (CGRect, NSScreen, CaptureMode) -> Void, screen: NSScreen,
         modeInteraction: CaptureModeInteraction) {
        self.onCapture = onCapture
        self.screen = screen
        self.modeInteraction = modeInteraction
        self.modeSelection = modeInteraction.selection
        
        let mouseLoc = NSEvent.mouseLocation
        let isInside = NSMouseInRect(mouseLoc, screen.frame, false)
        _isMouseInside = State(initialValue: isInside)
        if isInside {
            let localX = mouseLoc.x - screen.frame.origin.x
            let localY = screen.frame.height - (mouseLoc.y - screen.frame.origin.y)
            _mouseLocation = State(initialValue: CGPoint(x: localX, y: localY))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.3)
                if let selectionRect = selectionRectangle() {
                    Rectangle().fill(Color.white)
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .blendMode(.destinationOut)
                }
                if let selectionRect = selectionRectangle() {
                    Rectangle().stroke(Color.white, lineWidth: 1)
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .accessibilityLabel(Text("Selection rectangle at \(Int(selectionRect.origin.x)), \(Int(selectionRect.origin.y)) with size \(Int(selectionRect.width)) by \(Int(selectionRect.height))"))
                }
                if isMouseInside {
                    CrosshairShape().stroke(Color.white, lineWidth: 1)
                        .frame(width: 4000, height: 4000)
                        .position(mouseLocation)
                }
            }
            .compositingGroup()
            .overlay(alignment: .topLeading) {
                if let pressPoint = modeInteraction.pressPoint {
                    RadialCaptureMenu(descriptors: CaptureModeDescriptor.available,
                                      candidateIndex: modeInteraction.candidateIndex)
                        .position(modeInteraction.menuCenter ?? pressPoint)
                }
            }
            .overlay(alignment: .topLeading) {
                if isMouseInside, modeInteraction.pressPoint == nil,
                   let descriptor = CaptureModeDescriptor.descriptor(for: modeSelection.mode) {
                    Text(descriptor.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .fixedSize()
                        .background(GeometryReader { labelGeometry in
                            Color.clear.preference(key: ModeLabelSizeKey.self, value: labelGeometry.size)
                        })
                        .onPreferenceChange(ModeLabelSizeKey.self) { modeLabelSize = $0 }
                        .position(
                            x: min(max(mouseLocation.x + modeLabelSize.width / 2 + 12,
                                       modeLabelSize.width / 2),
                                   geometry.size.width - modeLabelSize.width / 2),
                            y: min(max(mouseLocation.y + modeLabelSize.height / 2 + 12,
                                       modeLabelSize.height / 2),
                                   geometry.size.height - modeLabelSize.height / 2)
                        )
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
            .gesture(dragGesture(in: geometry))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    self.isMouseInside = true
                    self.mouseLocation = location
                case .ended:
                    self.isMouseInside = false
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Screen capture area. Drag to select a region; right click to choose a capture mode."))
        }
        .preferredColorScheme(SettingsManager.shared.appearance.colorScheme)
    }

    private func selectionRectangle() -> CGRect? {
        guard let start = startPoint, let end = endPoint else { return nil }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
    }

    private func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                self.isMouseInside = true
                if self.startPoint == nil { self.startPoint = value.location }
                self.endPoint = value.location
                self.mouseLocation = value.location
            }
            .onEnded { value in
                guard let localRect = selectionRectangle(), localRect.width > 5, localRect.height > 5 else {
                    onCapture(.zero, screen, modeSelection.mode)
                    return
                }
                onCapture(localRect, screen, modeSelection.mode)
            }
    }
}

private struct ModeLabelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

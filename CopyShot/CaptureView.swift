//
//  CaptureView.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI

struct CaptureView: View {
    @State private var startPoint: CGPoint?
    @State private var endPoint: CGPoint?
    @State private var mouseLocation: CGPoint = .zero
    let onCapture: (CGRect) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.3)
                if let selectionRect = selectionRectangle() {
                    Rectangle().fill(Color.clear)
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .blendMode(.destinationOut)
                }
                if let selectionRect = selectionRectangle() {
                    Rectangle().stroke(Color.white, lineWidth: 1)
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                }
                CrosshairShape().stroke(Color.white, lineWidth: 1)
                    .frame(width: 4000, height: 4000)
                    .position(mouseLocation)
            }
            .compositingGroup()
            .ignoresSafeArea()
            .gesture(dragGesture(in: geometry))
            .onContinuousHover { phase in
                if case .active(let location) = phase { self.mouseLocation = location }
            }
        }
    }

    private func selectionRectangle() -> CGRect? {
        guard let start = startPoint, let end = endPoint else { return nil }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
    }

    private func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if self.startPoint == nil { self.startPoint = value.location }
                self.endPoint = value.location
                self.mouseLocation = value.location
            }
            .onEnded { value in
                guard let localRect = selectionRectangle(), localRect.width > 5, localRect.height > 5 else {
                    onCapture(.zero)
                    return
                }
                let globalRect = CGRect(
                    x: geometry.frame(in: .global).origin.x + localRect.origin.x,
                    y: geometry.frame(in: .global).origin.y + localRect.origin.y,
                    width: localRect.width,
                    height: localRect.height
                )
                onCapture(globalRect)
            }
    }
}

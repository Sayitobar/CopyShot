//
//  CaptureView.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI

struct CaptureView: View {
    // For drawing the selection rectangle
    @State private var startPoint: CGPoint?
    @State private var endPoint: CGPoint?
    
    // For drawing the custom crosshair
    @State private var mouseLocation: CGPoint = .zero
    
    // This is just a function that the view will call when it's done.
    let onCapture: (CGRect) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Semi-transparent overlay
                Color.black.opacity(0.4)
                
                // The selected area will be clear (Hole)
                if let selectionRect = selectionRectangle() {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .blendMode(.destinationOut) // This "cuts out" the black overlay
                }
                
                // Custom Crosshair
                CrosshairShape()
                    .stroke(Color.gray, lineWidth: 1)
                    .frame(width: geometry.size.width * 2, height: geometry.size.height * 2)  // Make it huge
                    .position(mouseLocation)  // Position it at the mouse

                // White border around the selection
                if let selectionRect = selectionRectangle() {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                }
                
                // Live Dimensions HUD
                if let selectionRect = selectionRectangle() {
                    let width = Int(selectionRect.width)
                    let height = Int(selectionRect.height)

                    Text("\(width) × \(height)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                        .position(
                            x: selectionRect.midX,
                            y: selectionRect.minY - 20
                        )
                        //.animation(.easeOut(duration: 0.15), value: selectionRect)
                }
            }
            .compositingGroup() // Necessary for the blendMode to work correctly
            .gesture(dragGesture(in: geometry)) // Attach our drag gesture
            .ignoresSafeArea()
            .onTapGesture {
                onCapture(.zero)
            }
            // Continuously track the mouse position
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    self.mouseLocation = location
                }
            }
        }
    }

    // A helper function to calculate the CGRect from the start and end points
    private func selectionRectangle() -> CGRect? {
        guard let start = startPoint, let end = endPoint else { return nil }
        return CGRect(x: min(start.x, end.x),
                      y: min(start.y, end.y),
                      width: abs(start.x - end.x),
                      height: abs(start.y - end.y))
    }

    // The main gesture recognizer for drawing the rectangle
    private func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if startPoint == nil {
                    // First touch, record the start point
                    startPoint = value.location
                }
                // Update the end point as the user drags
                endPoint = value.location
                mouseLocation = value.location  // Also update during drag
            }
            .onEnded { value in
                guard let rect = selectionRectangle() else {
                    // If for some reason there's no rect, just close
                    onCapture(.zero)
                    return
                }
                
                // We have the final rectangle.
                // We must convert it from local view coordinates to global screen coordinates.
                // The window's origin (0,0) is at the top-left of the screen.
                let screenRect = CGRect(
                    x: geometry.frame(in: .global).origin.x + rect.origin.x,
                    y: geometry.frame(in: .global).origin.y + rect.origin.y,
                    width: rect.width,
                    height: rect.height
                )
                
                // Call the completion handler with the final screen rectangle
                onCapture(screenRect)
            }
    }
}

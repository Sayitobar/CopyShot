//
//  CrosshairShape.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI

struct CrosshairShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Horizontal line
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        // Vertical line
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

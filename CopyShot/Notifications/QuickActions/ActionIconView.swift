//
//  ActionIconView.swift
//  CopyShot
//
//  Created by Mac on 26.09.26.
//

import SwiftUI
import AppKit

// MARK: - Action Icon Renderer

/// High-performance programmatic renderer for Quick Action icons and baseline-aligned typographic ligatures.
enum ActionIconRenderer {
    
    private static let iconCache = NSCache<NSString, NSImage>()
    
    /// Loads an SF Symbol by name, resolving standard symbols and private system symbols (e.g. `text.line.2.summary`).
    static func image(forSymbol name: String) -> NSImage? {
        let key = name as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        
        var resolvedImage: NSImage?
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            resolvedImage = img
        } else if let bundle = Bundle(path: "/System/Library/CoreServices/CoreGlyphsPrivate.bundle"),
                  let img = bundle.image(forResource: name) {
            resolvedImage = img
        }
        
        if let img = resolvedImage {
            img.isTemplate = true
            iconCache.setObject(img, forKey: key)
            return img
        }
        return nil
    }
    
    /// Generates a vector template image for letter pairs (`AA`, `aa`, `Aa`, `aA`) with exact optical bounding-box centering.
    static func typographyImage(text: String, size: CGFloat) -> NSImage? {
        let key = "typo_\(text)_\(Int(size))" as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        
        let fontSize = size * 0.72
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            let str = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
                .kern: -0.35
            ])
            let line = CTLineCreateWithAttributedString(str)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            
            // Optical centering derived deterministically from CoreText glyph path geometry
            let baselineX = (rect.width - bounds.width) / 2 - bounds.origin.x
            let baselineY = (rect.height - bounds.height) / 2 - bounds.origin.y
            
            ctx.textPosition = CGPoint(x: baselineX, y: baselineY)
            CTLineDraw(line, ctx)
            return true
        }
        img.isTemplate = true
        iconCache.setObject(img, forKey: key)
        return img
    }
}

// MARK: - Shared Action Icon View

/// A unified icon view used identically in both Action Shelf pills and the follow-up Notification HUD.
struct ActionIconView: View {
    let icon: ActionIcon
    let size: CGFloat
    var isHovered: Bool = false
    var accentColor: Color = .accentColor
    
    var body: some View {
        Group {
            switch icon {
            case .system(let name):
                if let nsImage = ActionIconRenderer.image(forSymbol: name) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .foregroundStyle(isHovered ? accentColor : .primary)
                } else {
                    Image(systemName: "arrow.right.to.line")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .foregroundStyle(isHovered ? accentColor : .primary)
                }
                
            case .typography(let string):
                if let nsImage = ActionIconRenderer.typographyImage(text: string, size: size) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: size, height: size)
                        .foregroundStyle(isHovered ? accentColor : .primary)
                } else {
                    Text(string)
                        .font(.system(size: size * 0.72, weight: .semibold, design: .default))
                        .tracking(-0.35)
                        .foregroundStyle(isHovered ? accentColor : .primary)
                }
            }
        }
    }
}

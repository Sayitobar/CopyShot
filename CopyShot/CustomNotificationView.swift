//
//  CustomNotificationView.swift
//  CopyShot
//
//  Created by Mac on 02.07.25.
//

import SwiftUI

struct CustomNotificationView: View {
    let title: String
    let subtitle: String?
    let bodyText: String
    let iconName: String
    let accentColor: Color
    
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(accentColor)
                    .padding(.trailing, 4)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        // Subtitle: Explanation text (Brighter, Primary)
                        Text(subtitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Body: Preview Text (Darker, Secondary)
                    Text(bodyText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
            .shadow(radius: 8)
            .padding(.horizontal)
            .fixedSize(horizontal: false, vertical: true) // Allow content to dictate height
            .frame(minHeight: 60) // Ensure a minimum height
            .offset(y: isVisible ? 0 : -150) // Adjusted offset for smoother animation
            .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: isVisible)
        }
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .opacity(isVisible ? 1 : 0) // Apply opacity for fade-in/out
        .animation(.easeIn(duration: 0.2), value: isVisible)
        .onAppear {
            isVisible = true
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: ViewHeightKey.self, value: geometry.size.height)
        })
    }
}

struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

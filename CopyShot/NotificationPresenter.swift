//
//  NotificationPresenter.swift
//  CopyShot
//
//  Created by Mac on 02.07.25.
//

import Foundation
import SwiftUI
import Combine
import AppKit // For NSWindow

class NotificationPresenter: ObservableObject {
    @Published var isShowingNotification: Bool = false
    @Published var notificationTitle: String = ""
    @Published var notificationSubtitle: String? = nil
    @Published var notificationBody: String = ""
    @Published var notificationIconName: String = ""
    @Published var notificationAccentColor: Color = .blue
    
    private var dismissTimer: AnyCancellable?
    private var notificationWindow: NSWindow?
    private var hostingView: NSHostingView<AnyView>? // Keep a reference to the hosting view
    
    func showNotification(
        title: String,
        subtitle: String? = nil,
        body: String,
        iconName: String,
        accentColor: Color,
        duration: TimeInterval = 3.0
    ) {
        // Dismiss any existing notification first
        dismissNotification()
        
        notificationTitle = title
        notificationSubtitle = subtitle
        notificationBody = body
        notificationIconName = iconName
        notificationAccentColor = accentColor
        isShowingNotification = true
        
        // Create and show the window
        if notificationWindow == nil {
            notificationWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), // Initial size, will be adjusted by fittingSize
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            notificationWindow?.isOpaque = false
            notificationWindow?.backgroundColor = .clear
            notificationWindow?.level = .floating // Make it float above other apps
            notificationWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            notificationWindow?.hidesOnDeactivate = false // Keep it visible even if app loses focus
        }
        
        // Host the SwiftUI view in the window
        let notificationView = CustomNotificationView(
            title: notificationTitle,
            subtitle: notificationSubtitle,
            bodyText: notificationBody,
            iconName: notificationIconName,
            accentColor: accentColor,
            isVisible: Binding(
                get: { [weak self] in self?.isShowingNotification ?? false },
                set: { [weak self] newValue in self?.isShowingNotification = newValue }
            )
        )
        .preferredColorScheme(SettingsManager.shared.appearance.colorScheme)

        hostingView = NSHostingView(rootView: AnyView(notificationView))
        notificationWindow?.contentView = hostingView
        
        // Calculate fitting size and set window frame
        let fittingSize = hostingView?.fittingSize ?? NSSize(width: 400, height: 100) // Fallback size
        updateWindowFrame(with: fittingSize)
        
        notificationWindow?.makeKeyAndOrderFront(nil)
        
        dismissTimer = Just(true)
            .delay(for: .seconds(duration), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideNotificationWithAnimation()
            }
    }
    
    func dismissNotification() {
        isShowingNotification = false
        dismissTimer?.cancel()
        dismissTimer = nil
        notificationWindow?.orderOut(nil)
        hostingView = nil // Release hosting view
    }
    
    private func hideNotificationWithAnimation() {
        // Trigger fade-out animation by setting isShowingNotification to false
        isShowingNotification = false
        
        // After animation, dismiss the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // Match animation duration
            self.dismissNotification()
        }
    }
    
    private func updateWindowFrame(with size: NSSize) {
        guard let screen = NSScreen.main, let window = notificationWindow else { return }
        
        let windowWidth = size.width + 40 // Add padding for horizontal margins
        let windowHeight = size.height + 40 // Add padding for vertical margins
        
        let xPos = screen.frame.maxX - windowWidth - 20
        let yPos = screen.frame.maxY - windowHeight - 20
        
        window.setFrame(NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight), display: true)
    }
}

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
    @Published var notificationFullBody: String? = nil
    @Published var notificationIconName: String = ""
    @Published var notificationAccentColor: Color = .orange
    
    private var dismissTimer: AnyCancellable?
    private var notificationWindow: NSWindow?
    private var hostingView: NSHostingView<AnyView>? // Keep a reference to the hosting view
    
    func showNotification(
        title: String,
        subtitle: String? = nil,
        body: String,
        fullBody: String? = nil,
        iconName: String,
        accentColor: Color,
        duration: TimeInterval = 3.0
    ) {
        // Dismiss any existing notification first
        dismissNotification()
        
        notificationTitle = title
        notificationSubtitle = subtitle
        notificationBody = body
        notificationFullBody = fullBody
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
            fullBodyText: notificationFullBody,
            iconName: notificationIconName,
            accentColor: accentColor,
            isVisible: Binding(
                get: { [weak self] in self?.isShowingNotification ?? false },
                set: { [weak self] newValue in self?.isShowingNotification = newValue }
            ),
            onHoverEnter: { [weak self] in 
                self?.cancelDismissTimer() 
            },
            onHoverExit: { [weak self] in 
                self?.startDismissTimer() 
            },
            onClose: { [weak self] in
                self?.hideNotificationWithAnimation()
            },
            onHeightChange: { [weak self] newHeight in
                guard let self = self, let _ = self.hostingView else { return }
                self.updateWindowFrame(with: NSSize(width: 384, height: newHeight))
            }
        )
        .preferredColorScheme(SettingsManager.shared.appearance.colorScheme)

        hostingView = NSHostingView(rootView: AnyView(notificationView))
        notificationWindow?.contentView = hostingView
        
        // Calculate fitting size and set window frame
        let fittingSize = hostingView?.fittingSize ?? NSSize(width: 400, height: 100) // Fallback size
        updateWindowFrame(with: fittingSize)
        
        notificationWindow?.alphaValue = 1.0 // Reset alpha before showing
        notificationWindow?.makeKeyAndOrderFront(nil)
        
        startDismissTimer()
    }
    
    func startDismissTimer() {
        dismissTimer?.cancel()
        dismissTimer = Just(true)
            .delay(for: .seconds(3.0), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideNotificationWithAnimation()
            }
    }
    
    func cancelDismissTimer() {
        dismissTimer?.cancel()
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
        self.isShowingNotification = false
        
        // Fast fadeout: animate window alpha to 0 for a native fade
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.notificationWindow?.animator().alphaValue = 0
        }) {
            self.dismissNotification()
        }
    }
    
    private func updateWindowFrame(with size: NSSize) {
        guard let screen = NSScreen.main, let window = notificationWindow else { return }
        
        let windowWidth = size.width
        let windowHeight = size.height
        
        // CustomNotificationView now has 20pt right padding and 8pt top padding.
        // We want approx 16pt margin from the right edge -> window right goes 4pt past the screen edge
        let xPos = screen.frame.maxX - windowWidth + 4
        // We want the visual box to be 8 points below the menu bar. 
        // Because the top padding is exactly 8pt, we just touch the window top to the menu bar (visibleFrame.maxY).
        // This avoids macOS forcefully clamping/snapping the window out of the menu bar reserved space!
        let yPos = screen.visibleFrame.maxY - windowHeight + 4
        
        window.setFrame(NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight), display: true)
    }
}

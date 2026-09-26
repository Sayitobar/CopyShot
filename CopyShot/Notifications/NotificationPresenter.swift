//
//  NotificationPresenter.swift
//  CopyShot
//
//  Created by Mac on 02.07.25.
//

import Foundation
import SwiftUI
import Combine
import AppKit

/// Specialized borderless floating window that can become key to intercept 1-9 quick action hotkeys on hover without warning
final class NotificationHUDWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}

/// Custom hosting view ensuring immediate first mouse acceptance and hover tracking
final class NotificationHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

class NotificationPresenter: ObservableObject {
    @Published var isShowingNotification: Bool = false
    @Published var notificationTitle: String = ""
    @Published var notificationSubtitle: String? = nil
    @Published var notificationBody: String = ""
    @Published var notificationFullBody: String? = nil
    @Published var notificationIconName: String = ""
    @Published var notificationCustomIcon: ActionIcon? = nil
    @Published var notificationAccentColor: Color = .orange
    @Published var isShelfOpen: Bool = false
    
    var targetScreen: NSScreen? = nil
    var supportsQuickActions: Bool = false
    var quickActions: [QuickAction] = QuickAction.defaultActions
    
    private var currentRawText: String? = nil
    private var dismissTimer: AnyCancellable?
    private var notificationWindow: NotificationHUDWindow?
    private var shelfWindow: NotificationHUDWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var shelfHostingView: NSHostingView<AnyView>?
    private var keyEventMonitor: Any?
    
    private var isHoveringNotification: Bool = false
    private var isHoveringShelf: Bool = false
    private var hoverOutWorkItem: DispatchWorkItem?
    private weak var previousApp: NSRunningApplication?
    
    private let fixedNotificationWindowWidth: CGFloat = 400
    
    // Geometry metrics for Shelf Window (with breathing margins for hover scaling & shadows)
    private let shelfPaddingLeading: CGFloat = ActionShelfView.paddingLeading
    private let shelfPaddingTop: CGFloat = ActionShelfView.paddingTop
    private let shelfPaddingBottom: CGFloat = ActionShelfView.paddingBottom
    private let shelfHoverGapTrailing: CGFloat = ActionShelfView.hoverGapTrailing
    private let shelfPillsWidth: CGFloat = 216
    
    private var shelfWindowWidth: CGFloat {
        shelfPaddingLeading + shelfPillsWidth + shelfHoverGapTrailing
    }
    
    private func calculateShelfWindowHeight(actionCount: Int) -> CGFloat {
        let count = CGFloat(actionCount)
        guard count > 0 else { return 0 }
        let pillsHeight = count * 38 + (count - 1) * 6
        return shelfPaddingTop + pillsHeight + shelfPaddingBottom
    }
    
    func showNotification(
        title: String,
        subtitle: String? = nil,
        body: String,
        fullBody: String? = nil,
        iconName: String = "checkmark.circle.fill",
        customIcon: ActionIcon? = nil,
        accentColor: Color,
        targetScreen: NSScreen? = nil,
        duration: TimeInterval = 3.0,
        supportsQuickActions: Bool = false,
        quickActions: [QuickAction] = QuickAction.defaultActions
    ) {
        // Dismiss any existing notification first
        dismissNotification()
        
        self.targetScreen = targetScreen
        self.supportsQuickActions = supportsQuickActions
        self.quickActions = quickActions
        self.currentRawText = fullBody ?? body
        self.isShelfOpen = false
        self.isHoveringNotification = false
        self.isHoveringShelf = false
        
        notificationTitle = title
        notificationSubtitle = subtitle
        notificationBody = body
        notificationFullBody = fullBody
        notificationIconName = iconName
        notificationCustomIcon = customIcon
        notificationAccentColor = accentColor
        isShowingNotification = true
        
        // Create window if needed
        if notificationWindow == nil {
            notificationWindow = NotificationHUDWindow(
                contentRect: NSRect(x: 0, y: 0, width: fixedNotificationWindowWidth, height: 100),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            notificationWindow?.isOpaque = false
            notificationWindow?.backgroundColor = .clear
            notificationWindow?.level = .floating // Make it float above other apps
            notificationWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            notificationWindow?.hidesOnDeactivate = false // Keep it visible even if app loses focus
            notificationWindow?.acceptsMouseMovedEvents = true // Intercept mouse move events so background apps don't react!
        }
        
        // Host the SwiftUI view in the window
        let notificationView = CustomNotificationView(
            title: notificationTitle,
            subtitle: notificationSubtitle,
            bodyText: notificationBody,
            fullBodyText: notificationFullBody,
            iconName: notificationIconName,
            customIcon: notificationCustomIcon,
            accentColor: accentColor,
            isVisible: Binding(
                get: { [weak self] in self?.isShowingNotification ?? false },
                set: { [weak self] newValue in self?.isShowingNotification = newValue }
            ),
            supportsQuickActions: supportsQuickActions,
            isShelfOpen: Binding(
                get: { [weak self] in self?.isShelfOpen ?? false },
                set: { [weak self] newValue in self?.isShelfOpen = newValue }
            ),
            onHoverEnter: { [weak self] in
                self?.handleNotificationHover(true)
            },
            onHoverExit: { [weak self] in
                self?.handleNotificationHover(false)
            },
            onClose: { [weak self] in
                self?.hideNotificationWithAnimation()
            },
            onHeightChange: { [weak self] newHeight in
                guard let self = self, let _ = self.hostingView else { return }
                DispatchQueue.main.async {
                    self.updateNotificationWindowHeight(newHeight)
                }
            },
            onExpandShelf: { [weak self] in
                self?.openActionShelf()
            }
        ).preferredColorScheme(SettingsManager.shared.appearance.colorScheme)

        let host = NotificationHostingView(rootView: AnyView(notificationView))
        hostingView = host
        notificationWindow?.contentView = host
        
        let initialHeight: CGFloat = hostingView?.fittingSize.height ?? 100
        updateNotificationWindowHeight(initialHeight)
        
        notificationWindow?.alphaValue = 1.0 // Reset alpha before showing
        notificationWindow?.orderFrontRegardless()
        
        #if DEBUG
        CaptureBenchmarkTracker.shared.recordHUDDisplayed()
        #endif
        
        startDismissTimer()
    }
    
    // MARK: - Shelf Window Management
    
    private func openActionShelf() {
        guard supportsQuickActions, let notifWindow = notificationWindow, let _ = targetScreen ?? NSScreen.main else { return }
        
        isShelfOpen = true
        
        // Calculate shelf window position:
        // Inside notificationWindow (400pt wide), notificationBox starts at origin.x + 44
        // Midpoint of the 8pt gap between shelf pills and notif box is at notifWindow.frame.origin.x + 40
        // The right edge of shelfWindow touches the midpoint boundary:
        let shelfX = (notifWindow.frame.origin.x + 40) - shelfWindowWidth
        
        // Top of notification box inside notificationWindow:
        let notifBoxTopY = notifWindow.frame.origin.y + notifWindow.frame.height - 14
        let shelfHeight = calculateShelfWindowHeight(actionCount: quickActions.count)
        
        // Top of the first pill is at shelfPaddingTop below the top of shelfWindow.
        // We want the top of the first pill to align with notifBoxTopY:
        // (shelfY + shelfHeight) - shelfPaddingTop = notifBoxTopY
        // => shelfY = notifBoxTopY + shelfPaddingTop - shelfHeight
        let shelfY = notifBoxTopY + shelfPaddingTop - shelfHeight
        
        let shelfFrame = NSRect(x: shelfX, y: shelfY, width: shelfWindowWidth, height: shelfHeight)
        
        if shelfWindow == nil {
            shelfWindow = NotificationHUDWindow(
                contentRect: shelfFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            shelfWindow?.isOpaque = false
            shelfWindow?.backgroundColor = .clear
            shelfWindow?.level = .floating
            shelfWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            shelfWindow?.hidesOnDeactivate = false
            shelfWindow?.acceptsMouseMovedEvents = true
        } else {
            shelfWindow?.setFrame(shelfFrame, display: true)
        }
        
        let shelfView = ActionShelfView(
            actions: quickActions,
            accentColor: notificationAccentColor,
            onActionSelected: { [weak self] action in
                self?.triggerQuickAction(action)
            },
            onHoverChange: { [weak self] hovering in
                self?.handleShelfHover(hovering)
            }
        ).preferredColorScheme(SettingsManager.shared.appearance.colorScheme)
        
        let shelfHost = NotificationHostingView(rootView: AnyView(shelfView))
        shelfHostingView = shelfHost
        shelfWindow?.contentView = shelfHost
        
        shelfWindow?.alphaValue = 0
        shelfWindow?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shelfWindow?.animator().alphaValue = 1.0
        }
        
        cancelDismissTimer()
        startKeyMonitoring()
    }
    
    private func closeActionShelfWithAnimation(completion: (() -> Void)? = nil) {
        guard isShelfOpen, let shelf = shelfWindow else {
            completion?()
            return
        }
        isShelfOpen = false
        stopKeyMonitoring()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shelf.animator().alphaValue = 0
        }) {
            shelf.orderOut(nil)
            self.shelfHostingView = nil
            completion?()
        }
    }
    
    private func closeActionShelfInstantly() {
        isShelfOpen = false
        shelfWindow?.orderOut(nil)
        shelfHostingView = nil
    }
    
    // MARK: - Dismissal Timers
    
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
        stopKeyMonitoring()
        closeActionShelfInstantly()
        isShowingNotification = false
        dismissTimer?.cancel()
        dismissTimer = nil
        notificationWindow?.orderOut(nil)
        hostingView = nil
    }
    
    private func hideNotificationWithAnimation(completion: (() -> Void)? = nil) {
        stopKeyMonitoring()
        self.isShowingNotification = false
        self.isShelfOpen = false
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.notificationWindow?.animator().alphaValue = 0
            self.shelfWindow?.animator().alphaValue = 0
        }) {
            self.dismissNotification()
            completion?()
        }
    }
    
    // MARK: - Static Window Positioning (Zero Teleportation)
    
    private func updateNotificationWindowHeight(_ height: CGFloat) {
        guard let screen = targetScreen ?? NSScreen.main, let window = notificationWindow else { return }
        
        let windowWidth = fixedNotificationWindowWidth
        let windowHeight = height + 42 // Account for vertical paddings (14 top + 28 bottom)
        
        // Pinned to top-right corner. Window width is constant (400pt), origin X is 100% stationary!
        let xPos = screen.frame.maxX - windowWidth + 4
        let yPos = screen.visibleFrame.maxY - windowHeight + 4
        
        let newFrame = NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight)
        if window.frame != newFrame {
            window.setFrame(newFrame, display: true)
        }
    }
    
    // MARK: - Hover Handlers & Separate Focus
    
    private func handleNotificationHover(_ hovering: Bool) {
        isHoveringNotification = hovering
        
        if hovering {
            hoverOutWorkItem?.cancel()
            hoverOutWorkItem = nil
            cancelDismissTimer()
            startKeyMonitoring()
        } else {
            evaluateHoverOut()
        }
    }
    
    private func handleShelfHover(_ hovering: Bool) {
        isHoveringShelf = hovering
        
        if hovering {
            hoverOutWorkItem?.cancel()
            hoverOutWorkItem = nil
            cancelDismissTimer()
            startKeyMonitoring()
        } else {
            evaluateHoverOut()
        }
    }
    
    private func evaluateHoverOut() {
        // Debounce slightly (80ms) to allow seamless mouse travel between ActionShelf and Notification without touching desktop
        hoverOutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // If the cursor is on desktop (neither shelf nor notification is hovered):
            // ActionShelf fades out smoothly (0.2s), and after 3s the notification disappears!
            if !self.isHoveringShelf && !self.isHoveringNotification {
                self.closeActionShelfWithAnimation()
                self.startDismissTimer()
            }
        }
        hoverOutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }
    
    // MARK: - Keyboard Monitoring (1-9 Direct Access)
    
    private func startKeyMonitoring() {
        stopKeyMonitoring()
        guard supportsQuickActions else { return }
        
        // Remember frontmost application to restore focus when hover ends
        if previousApp == nil {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        
        // Make notification window key to receive hotkeys
        notificationWindow?.makeKey()
        
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, (self.isHoveringNotification || self.isHoveringShelf), self.supportsQuickActions else {
                return event
            }
            
            if let chars = event.charactersIgnoringModifiers,
               let digit = Int(chars),
               (1...9).contains(digit) {
                if let action = self.quickActions.first(where: { $0.shortcutNumber == digit }) {
                    self.triggerQuickAction(action)
                    return nil // Swallow keystroke
                }
            }
            return event
        }
    }
    
    private func stopKeyMonitoring() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        
        if let app = previousApp {
            app.activate(options: [])
            previousApp = nil
        }
    }
    
    // MARK: - Action Execution & Feedback
    
    func triggerQuickAction(_ action: QuickAction) {
        guard let rawText = currentRawText, !rawText.isEmpty else { return }
        
        // Tactile Mac feedback & sound
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        FeedbackManager.playSuccessSound()
        
        // Fade out existing bars and notification HUD
        hideNotificationWithAnimation { [weak self] in
            guard let self = self else { return }
            
            // Execute preprocessing transformation
            let transformedText = action.transform(rawText)
            
            // Copy newly preprocessed text to clipboard
            ClipboardManager.copyToClipboard(text: transformedText)
            
            // Format preview text
            let previewText: String
            if SettingsManager.shared.textPreviewLimit > 0 && transformedText.count > SettingsManager.shared.textPreviewLimit {
                previewText = String(transformedText.prefix(SettingsManager.shared.textPreviewLimit)) + "..."
            } else {
                previewText = transformedText
            }
            
            // Present new notification with Quick Action tag and chained quick action support
            FeedbackManager.showNotification(
                title: "Quick Action: \(action.title)",
                subtitle: "Processed text:",
                body: previewText,
                fullBody: transformedText,
                customIcon: action.icon,
                accentColor: .adaptiveGreen,
                soundName: "Funk",
                targetScreen: self.targetScreen,
                supportsQuickActions: true
            )
        }
    }
}

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
    var isHitInNotificationBox: ((NSPoint) -> Bool)?
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let isHit = isHitInNotificationBox {
            if !isHit(point) {
                return nil
            }
        }
        return super.hitTest(point)
    }
}

class NotificationPresenter: ObservableObject {
    static func isPointInVisibleBox(_ point: NSPoint, windowHeight: CGFloat, visibleBoxHeight: CGFloat) -> Bool {
        let boxHeight = max(visibleBoxHeight, 78)
        let thresholdY = windowHeight - 14 - boxHeight - 20
        return point.y >= thresholdY && point.y <= windowHeight + 10
    }

    private let configProvider: () -> QuickActionsConfig
    private let dismissScheduler: (TimeInterval, @escaping () -> Void) -> AnyCancellable

    init(
        configProvider: @escaping () -> QuickActionsConfig = { SettingsManager.shared.quickActionsConfig },
        dismissScheduler: @escaping (TimeInterval, @escaping () -> Void) -> AnyCancellable = { duration, action in
        Just(true)
            .delay(for: .seconds(duration), scheduler: DispatchQueue.main)
            .sink { _ in action() }
        }
    ) {
        self.configProvider = configProvider
        self.dismissScheduler = dismissScheduler
    }

    @Published var isShowingNotification: Bool = false
    @Published var notificationTitle: String = ""
    @Published var notificationSubtitle: String? = nil
    @Published var notificationBody: String = ""
    @Published var notificationFullBody: String? = nil
    @Published var notificationIconName: String = ""
    @Published var notificationCustomIcon: ActionIcon? = nil
    @Published var notificationAccentColor: Color = .orange
    @Published var isShelfOpen: Bool = false
    @Published var activeSubmenu: QuickAction? = nil
    @Published var isHoveringSubShelf: Bool = false
    
    var targetScreen: NSScreen? = nil
    var supportsQuickActions: Bool = false
    var quickActions: [QuickAction] = QuickAction.defaultActions
    
    private var currentRawText: String? = nil
    private var dismissTimer: AnyCancellable?
    private var notificationDuration: TimeInterval = 3.0
    private var notificationWindow: NotificationHUDWindow?
    private var shelfWindow: NotificationHUDWindow?
    private var subShelfWindow: NotificationHUDWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var shelfHostingView: NSHostingView<AnyView>?
    private var subShelfHostingView: NSHostingView<AnyView>?
    private var keyEventMonitor: Any?
    
    private var isHoveringNotification: Bool = false
    private var isHoveringShelf: Bool = false
    private var currentHoveredAction: QuickAction?
    private var hoverOutWorkItem: DispatchWorkItem?
    private var hoverGraceTimer: DispatchWorkItem?
    private var subShelfCloseToken: UUID?
    private weak var previousApp: NSRunningApplication?
    private var shelfLivenessTimer: Timer?
    
    private let fixedNotificationWindowWidth: CGFloat = 400
    private var currentVisibleBoxHeight: CGFloat = 78
    
    /// Deterministically computed bounding box of the visible notification HUD box (inside the 400pt notificationWindow).
    /// Used for strict hit-testing to prevent transparent window margins from hijacking hover states.
    private var visibleNotificationBoxFrame: NSRect? {
        guard let window = notificationWindow, isShowingNotification, window.isVisible else { return nil }
        let boxWidth: CGFloat = 376 // Covers 28pt left arrow + 4pt gap + 344pt notification box
        let boxHeight = currentVisibleBoxHeight > 0 ? currentVisibleBoxHeight : max(window.frame.height - 42, 0)
        let boxX = window.frame.origin.x + 12
        let boxY = (window.frame.origin.y + window.frame.height - 14) - boxHeight
        return NSRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)
    }
    
    private func startShelfLivenessTracking() {
        stopShelfLivenessTracking()
        shelfLivenessTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMouseLiveness()
        }
    }
    
    private func stopShelfLivenessTracking() {
        shelfLivenessTimer?.invalidate()
        shelfLivenessTimer = nil
    }
    
    private func checkMouseLiveness() {
        guard isShelfOpen else {
            stopShelfLivenessTracking()
            return
        }
        
        let mouseLoc = NSEvent.mouseLocation
        let isOverMainShelf = shelfWindow?.frame.contains(mouseLoc) ?? false
        let isOverSubShelf = (activeSubmenu != nil) && (subShelfWindow?.frame.contains(mouseLoc) ?? false)
        let isOverNotifBox = visibleNotificationBoxFrame?.contains(mouseLoc) ?? false
        
        if !isOverMainShelf && !isOverSubShelf && !isOverNotifBox {
            stopShelfLivenessTracking()
            closeActionShelfWithAnimation()
            startDismissTimer()
        }
    }
    
    // Geometry metrics for Shelf Window (with breathing margins for hover scaling & shadows)
    private let shelfPaddingLeading: CGFloat = ActionShelfView.paddingLeading
    private let shelfPaddingTop: CGFloat = ActionShelfView.paddingTop
    private let shelfPaddingBottom: CGFloat = ActionShelfView.paddingBottom
    private let shelfHoverGapTrailing: CGFloat = ActionShelfView.hoverGapTrailing
    private let shelfPillsWidth: CGFloat = ActionShelfView.pillWidth
    private let shelfColumnGap: CGFloat = ActionShelfView.columnGap
    
    private var mainShelfWindowWidth: CGFloat {
        shelfPaddingLeading + shelfPillsWidth + shelfHoverGapTrailing
    }
    
    private var subShelfWindowWidth: CGFloat {
        shelfPaddingLeading + shelfPillsWidth + shelfColumnGap
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
        quickActions: [QuickAction]? = nil
    ) {
        // Dismiss any existing notification first
        dismissNotification()
        
        let config = configProvider()
        self.targetScreen = targetScreen
        self.supportsQuickActions = supportsQuickActions && config.isEnabled
        self.currentRawText = fullBody ?? body
        self.quickActions = quickActions ?? QuickAction.actions(for: self.currentRawText, config: config)
        self.notificationDuration = max(0, duration)
        self.isShelfOpen = false
        self.activeSubmenu = nil
        self.hoverGraceTimer?.cancel()
        self.hoverGraceTimer = nil
        self.currentVisibleBoxHeight = 78
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
            supportsQuickActions: self.supportsQuickActions,
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
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.currentVisibleBoxHeight = newHeight
                    if let win = self.notificationWindow, newHeight + 42 > win.frame.height {
                        self.updateNotificationWindowHeight(newHeight)
                    }
                }
            },
            onExpandShelf: { [weak self] in
                self?.openActionShelf()
            }
        ).preferredColorScheme(SettingsManager.shared.appearance.colorScheme)

        let host = NotificationHostingView(rootView: AnyView(notificationView))
        host.isHitInNotificationBox = { [weak self, weak host] point in
            guard let self = self, let host = host, let window = host.window ?? self.notificationWindow else {
                return true
            }
            // In AppKit window coordinates, (0, 0) is bottom-left. The notification is anchored at the top.
            return Self.isPointInVisibleBox(
                point, windowHeight: window.frame.height, visibleBoxHeight: self.currentVisibleBoxHeight
            )
        }
        hostingView = host
        notificationWindow?.contentView = host
        
        let screenHeight = (targetScreen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let initialHeight: CGFloat = min(screenHeight - 20, 800)
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
        activeSubmenu = nil
        isHoveringSubShelf = false
        hoverGraceTimer?.cancel()
        hoverGraceTimer = nil
        startShelfLivenessTracking()
        
        // Anchor calculation:
        // Inside notificationWindow (400pt wide), notificationBox starts at origin.x + 44
        // Midpoint of the 8pt gap between shelf pills and notif box is at notifWindow.frame.origin.x + 40
        // The right edge of shelfWindow touches the midpoint boundary:
        let width = mainShelfWindowWidth
        let shelfX = (notifWindow.frame.origin.x + 40) - width
        
        // Top of notification box inside notificationWindow:
        let notifBoxTopY = notifWindow.frame.origin.y + notifWindow.frame.height - 14
        let shelfHeight = calculateShelfWindowHeight(actionCount: quickActions.count)
        let shelfY = notifBoxTopY + shelfPaddingTop - shelfHeight
        
        let shelfFrame = NSRect(x: shelfX, y: shelfY, width: width, height: shelfHeight)
        
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
        
        setupMainShelfHostingView()
        
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
    
    private func setupMainShelfHostingView() {
        if shelfHostingView == nil {
            let container = ActionShelfContainerView(presenter: self)
            let host = NotificationHostingView(rootView: AnyView(container))
            shelfHostingView = host
            shelfWindow?.contentView = host
        }
    }
    
    private func openSubShelf(for action: QuickAction) {
        guard let shelf = shelfWindow, let notifWindow = notificationWindow, let subActions = action.subActions, !subActions.isEmpty else { return }
        
        // Invalidate any in-flight close animation block
        subShelfCloseToken = UUID()
        hoverGraceTimer?.cancel()
        hoverGraceTimer = nil
        
        activeSubmenu = action
        
        let subWidth = subShelfWindowWidth
        let subX = shelf.frame.origin.x - (shelfPillsWidth + shelfColumnGap)
        
        let notifBoxTopY = notifWindow.frame.origin.y + notifWindow.frame.height - 14
        let subHeight = calculateShelfWindowHeight(actionCount: subActions.count)
        let subY = notifBoxTopY + shelfPaddingTop - subHeight
        
        let subFrame = NSRect(x: subX, y: subY, width: subWidth, height: subHeight)
        
        if subShelfWindow == nil {
            subShelfWindow = NotificationHUDWindow(
                contentRect: subFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            subShelfWindow?.isOpaque = false
            subShelfWindow?.backgroundColor = .clear
            subShelfWindow?.level = .floating
            subShelfWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            subShelfWindow?.hidesOnDeactivate = false
            subShelfWindow?.acceptsMouseMovedEvents = true
        } else {
            subShelfWindow?.setFrame(subFrame, display: true)
        }
        
        let subView = ActionSubShelfView(
            subActions: subActions,
            accentColor: notificationAccentColor,
            onActionSelected: { [weak self] selectedAction in
                self?.triggerQuickAction(selectedAction)
            },
            onHoverChange: { [weak self] hovering in
                self?.handleSubShelfHover(hovering)
            }
        ).preferredColorScheme(SettingsManager.shared.appearance.colorScheme)
        
        if let host = subShelfHostingView {
            host.rootView = AnyView(subView)
        } else {
            let host = NotificationHostingView(rootView: AnyView(subView))
            subShelfHostingView = host
            subShelfWindow?.contentView = host
        }
        
        subShelfWindow?.orderFrontRegardless()
        if subShelfWindow?.alphaValue ?? 0 < 1.0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                subShelfWindow?.animator().alphaValue = 1.0
            }
        }
    }
    
    private func closeSubShelfWithAnimation(completion: (() -> Void)? = nil) {
        activeSubmenu = nil
        isHoveringSubShelf = false
        
        guard let subShelf = subShelfWindow, subShelf.isVisible else {
            completion?()
            return
        }
        
        let closeToken = UUID()
        self.subShelfCloseToken = closeToken
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            subShelf.animator().alphaValue = 0
        }) { [weak self] in
            guard let self = self, self.subShelfCloseToken == closeToken else {
                completion?()
                return
            }
            subShelf.orderOut(nil)
            self.subShelfHostingView = nil
            completion?()
        }
    }
    
    private func closeSubShelfInstantly() {
        subShelfCloseToken = UUID()
        activeSubmenu = nil
        isHoveringSubShelf = false
        subShelfWindow?.orderOut(nil)
        subShelfHostingView = nil
    }
    
    fileprivate func handleMainPillHover(action: QuickAction, hovering: Bool) {
        if hovering {
            currentHoveredAction = action
            hoverGraceTimer?.cancel()
            hoverGraceTimer = nil
            
            if action.hasSubmenu {
                if activeSubmenu?.id != action.id {
                    openSubShelf(for: action)
                }
            } else {
                // If hovering an action without submenu, use brief grace period so fast sweeps between submenus don't drop the shelf
                if activeSubmenu != nil {
                    scheduleSubmenuDismissal(delay: 0.18)
                }
            }
        } else {
            if currentHoveredAction?.id == action.id {
                currentHoveredAction = nil
            }
            scheduleSubmenuDismissal(delay: 0.25)
        }
    }
    
    fileprivate func handleSubShelfHover(_ hovering: Bool) {
        isHoveringSubShelf = hovering
        
        if hovering {
            hoverGraceTimer?.cancel()
            hoverGraceTimer = nil
            hoverOutWorkItem?.cancel()
            hoverOutWorkItem = nil
            cancelDismissTimer()
            startKeyMonitoring()
        } else {
            scheduleSubmenuDismissal(delay: 0.25)
        }
    }
    
    private func scheduleSubmenuDismissal(delay: TimeInterval = 0.25) {
        hoverGraceTimer?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isShelfOpen, self.activeSubmenu != nil else { return }
            
            // If the cursor is currently hovering an action that has a submenu, keep its sub-shelf open!
            if let current = self.currentHoveredAction, current.hasSubmenu {
                if self.activeSubmenu?.id != current.id {
                    self.openSubShelf(for: current)
                }
                return
            }
            
            let mouseLoc = NSEvent.mouseLocation
            let isOverSub = self.subShelfWindow?.frame.contains(mouseLoc) ?? false
            let isOverMain = self.shelfWindow?.frame.contains(mouseLoc) ?? false
            
            if isOverSub {
                return
            }
            
            self.closeSubShelfWithAnimation()
            
            if !isOverMain {
                self.evaluateHoverOut()
            }
        }
        hoverGraceTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func closeActionShelfWithAnimation(completion: (() -> Void)? = nil) {
        stopShelfLivenessTracking()
        hoverGraceTimer?.cancel()
        hoverGraceTimer = nil
        isShelfOpen = false
        stopKeyMonitoring()
        
        guard let shelf = shelfWindow, shelf.isVisible else {
            closeSubShelfInstantly()
            completion?()
            return
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shelf.animator().alphaValue = 0
            self.subShelfWindow?.animator().alphaValue = 0
        }) {
            shelf.orderOut(nil)
            self.subShelfWindow?.orderOut(nil)
            self.shelfHostingView = nil
            self.subShelfHostingView = nil
            self.activeSubmenu = nil
            self.isHoveringSubShelf = false
            completion?()
        }
    }
    
    private func closeActionShelfInstantly() {
        stopShelfLivenessTracking()
        hoverGraceTimer?.cancel()
        hoverGraceTimer = nil
        activeSubmenu = nil
        isHoveringSubShelf = false
        isShelfOpen = false
        shelfWindow?.orderOut(nil)
        subShelfWindow?.orderOut(nil)
        shelfHostingView = nil
        subShelfHostingView = nil
    }
    
    // MARK: - Dismissal Timers
    
    func startDismissTimer() {
        dismissTimer?.cancel()
        dismissTimer = dismissScheduler(notificationDuration) { [weak self] in
            self?.hideNotificationWithAnimation()
        }
    }
    
    func cancelDismissTimer() {
        dismissTimer?.cancel()
    }
    
    func dismissNotification() {
        stopShelfLivenessTracking()
        stopKeyMonitoring()
        closeActionShelfInstantly()
        isShowingNotification = false
        dismissTimer?.cancel()
        dismissTimer = nil
        notificationWindow?.orderOut(nil)
        hostingView = nil
    }
    
    private func hideNotificationWithAnimation(completion: (() -> Void)? = nil) {
        stopShelfLivenessTracking()
        stopKeyMonitoring()
        self.isShowingNotification = false
        self.isShelfOpen = false
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.notificationWindow?.animator().alphaValue = 0
            self.shelfWindow?.animator().alphaValue = 0
            self.subShelfWindow?.animator().alphaValue = 0
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
    
    fileprivate func handleShelfHover(_ hovering: Bool) {
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
        hoverOutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Deterministically check cursor location against actual window frames and visible notification box
            let mouseLoc = NSEvent.mouseLocation
            let isOverMainShelf = self.isShelfOpen && (self.shelfWindow?.frame.contains(mouseLoc) ?? false)
            let isOverSubShelf = self.activeSubmenu != nil && (self.subShelfWindow?.frame.contains(mouseLoc) ?? false)
            let isOverNotif = self.visibleNotificationBoxFrame?.contains(mouseLoc) ?? false
            
            let isOverAnyShelf = isOverMainShelf || isOverSubShelf
            self.isHoveringShelf = isOverAnyShelf
            self.isHoveringNotification = isOverNotif
            
            // If the cursor is on desktop (neither shelf nor visible notification is hovered):
            // All action shelves fade out smoothly (0.2s), and after 3s the notification disappears!
            if !isOverAnyShelf && !isOverNotif {
                self.closeActionShelfWithAnimation()
                self.startDismissTimer()
            }
        }
        hoverOutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
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
            
            // Escape key closes active submenu flyout if open
            if event.keyCode == 53, self.activeSubmenu != nil {
                self.closeSubShelfWithAnimation()
                return nil
            }
            
            if let chars = event.charactersIgnoringModifiers,
               let digit = Int(chars),
               (1...9).contains(digit) {
                // If a submenu flyout is currently open, 1-9 shortcuts map to its sub-actions
                if let submenu = self.activeSubmenu,
                   let subActions = submenu.subActions,
                   let subAction = subActions.first(where: { $0.shortcutNumber == digit }) {
                    self.triggerQuickAction(subAction)
                    return nil
                } else if let action = self.quickActions.first(where: { $0.shortcutNumber == digit }) {
                    self.triggerQuickAction(action)
                    return nil
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
        
        // Slot 3: Search Web / Open URL (Zero confirmation notification on success)
        if action.id == "search_web" {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            FeedbackManager.playSuccessSound()
            
            hideNotificationWithAnimation { [weak self] in
                guard let self = self else { return }
                let engine = configProvider().searchEngine
                let success = WebActionHelper.execute(for: rawText, engine: engine)
                if !success {
                    FeedbackManager.showNotification(
                        title: "Unable to Open",
                        subtitle: "Could not open URL or search web",
                        body: rawText,
                        iconName: "exclamationmark.triangle.fill",
                        accentColor: .orange,
                        targetScreen: self.targetScreen
                    )
                }
            }
            return
        }
        
        // Slot 4 & Sub-actions: On-Device Translate (macOS 15+)
        if let targetLang = action.targetLanguageCode {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            FeedbackManager.playSuccessSound()
            
            hideNotificationWithAnimation { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    TranslationService.shared.translate(text: rawText, targetLanguageCode: targetLang) { [weak self] result in
                        guard let self = self else { return }
                        switch result {
                    case .success(let translation):
                        ClipboardManager.copyToClipboard(text: translation.translatedText)
                        
                        let previewText: String
                        previewText = TextPreview.format(
                            translation.translatedText,
                            limit: SettingsManager.shared.textPreviewLimit
                        )
                        
                        FeedbackManager.showNotification(
                            title: "Translated to \(translation.targetLanguageName)",
                            subtitle: "\(translation.sourceLanguageName) → \(translation.targetLanguageName)",
                            body: previewText,
                            fullBody: translation.translatedText,
                            customIcon: .system("translate"),
                            accentColor: .adaptiveGreen,
                            soundName: "Funk",
                            targetScreen: self.targetScreen,
                            supportsQuickActions: true
                        )
                        
                    case .failure(let error):
                        FeedbackManager.showNotification(
                            title: "Translation Failed",
                            subtitle: "Ensure language set is downloaded from Apple",
                            body: error.localizedDescription,
                            iconName: "exclamationmark.triangle.fill",
                            accentColor: .orange,
                            targetScreen: self.targetScreen
                        )
                    }
                }
            }
        }
        return
        }
        
        // Standard String Transformations (Join Lines, Case Transforms)
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

// MARK: - Action Shelf Reactive Container

private struct ActionShelfContainerView: View {
    @ObservedObject var presenter: NotificationPresenter
    
    var body: some View {
        ActionShelfView(
            actions: presenter.quickActions,
            accentColor: presenter.notificationAccentColor,
            activeSubmenuId: presenter.activeSubmenu?.id,
            isSubShelfHovered: presenter.isHoveringSubShelf,
            onActionSelected: { [weak presenter] action in
                presenter?.triggerQuickAction(action)
            },
            onMainPillHover: { [weak presenter] action, hovering in
                presenter?.handleMainPillHover(action: action, hovering: hovering)
            },
            onHoverChange: { [weak presenter] hovering in
                presenter?.handleShelfHover(hovering)
            }
        )
        .preferredColorScheme(SettingsManager.shared.appearance.colorScheme)
    }
}

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

@MainActor
class NotificationPresenter: ObservableObject {
    static func isPointInVisibleBox(_ point: NSPoint, windowHeight: CGFloat, visibleBoxHeight: CGFloat) -> Bool {
        let boxHeight = max(visibleBoxHeight, 78)
        let thresholdY = windowHeight - 14 - boxHeight - 20
        return point.y >= thresholdY && point.y <= windowHeight + 10
    }

    private let configProvider: () -> QuickActionsConfig
    private let actionExecutor: any ActionExecuting
    private let copyText: (String) -> Void
    private let openURL: (URL) -> Bool
    private let animationScheduler: ((@escaping () -> Void) -> Void)?
    private var executionTask: Task<Void, Never>?
    private var sessionGeneration = UUID()
    private(set) var currentActionContext: ActionContext?
    private let dismissScheduler: (TimeInterval, @escaping () -> Void) -> AnyCancellable

    init(
        actionExecutor: (any ActionExecuting)? = nil,
        copyText: @escaping (String) -> Void = { ClipboardManager.copyToClipboard(text: $0) },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        animationScheduler: ((@escaping () -> Void) -> Void)? = nil,
        configProvider: @escaping () -> QuickActionsConfig = { SettingsManager.shared.quickActionsConfig },
        dismissScheduler: @escaping (TimeInterval, @escaping () -> Void) -> AnyCancellable = { duration, action in
        Just(true)
            .delay(for: .seconds(duration), scheduler: DispatchQueue.main)
            .sink { _ in action() }
        }
    ) {
        self.actionExecutor = actionExecutor ?? BuiltInActionExecutor()
        self.copyText = copyText
        self.openURL = openURL
        self.animationScheduler = animationScheduler
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
    var currentCaptureMode: CaptureMode = .standardOCR
    
    private var mainShelfNaturalHeight: CGFloat = 0
    private var subShelfNaturalHeight: CGFloat = 0
    private var subShelfInteractiveFrame: NSRect?
    @Published fileprivate var mainShelfScrollHeight: CGFloat?
    @Published fileprivate var subShelfScrollHeight: CGFloat?
    @Published fileprivate var subShelfViewportHeight: CGFloat = 0
    private var shelfCloseToken = UUID()
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
    @Published var isHoveringShelf: Bool = false
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
            Task { @MainActor in self?.checkMouseLiveness() }
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
        let isOverSubShelf = (activeSubmenu != nil) && (subShelfInteractiveFrame?.contains(mouseLoc) ?? false)
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
        quickActions: [QuickAction]? = nil,
        captureMode: CaptureMode = .standardOCR,
        actionContext: ActionContext? = nil
    ) {
        // Dismiss any existing notification first
        dismissNotification()
        
        let config = configProvider()
        self.targetScreen = targetScreen
        let context = actionContext ?? ActionContext(text: fullBody ?? body, mode: captureMode)
        self.currentActionContext = context
        self.currentCaptureMode = context.mode
        self.quickActions = quickActions ?? ActionRegistry.shared.actions(context: context, config: config)
        mainShelfNaturalHeight = ShelfLayout.naturalHeight(actions: self.quickActions, submenu: false)
        subShelfNaturalHeight = self.quickActions.compactMap(\.subActions).map { ShelfLayout.naturalHeight(actions: $0, submenu: true) }.max() ?? 0
        self.supportsQuickActions = supportsQuickActions && config.isEnabled && !self.quickActions.isEmpty
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
        let generation = sessionGeneration
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
                    guard self.sessionGeneration == generation else { return }
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
        
        shelfCloseToken = UUID()
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
        let screen = targetScreen ?? NSScreen.main!
        let shelfTop = min(screen.visibleFrame.maxY, notifBoxTopY + shelfPaddingTop)
        let shelfHeight = ShelfLayout.viewportHeight(naturalHeight: mainShelfNaturalHeight, availableHeight: shelfTop - screen.visibleFrame.minY)
        mainShelfScrollHeight = mainShelfNaturalHeight > shelfHeight ? max(0, shelfHeight - shelfPaddingTop - shelfPaddingBottom) : nil
        let shelfY = shelfTop - shelfHeight
        
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
        guard let shelf = shelfWindow, let screen = targetScreen ?? NSScreen.main,
              let subActions = action.subActions, !subActions.isEmpty else { return }
        
        // Invalidate any in-flight close animation block
        subShelfCloseToken = UUID()
        hoverGraceTimer?.cancel()
        hoverGraceTimer = nil
        
        activeSubmenu = action
        
        let subWidth = subShelfWindowWidth
        let subX = shelf.frame.origin.x - (shelfPillsWidth + shelfColumnGap)
        
        let subHeight = ShelfLayout.viewportHeight(naturalHeight: subShelfNaturalHeight, availableHeight: shelf.frame.maxY - screen.visibleFrame.minY)
        let activeHeight = min(subHeight, ShelfLayout.naturalHeight(actions: subActions, submenu: true))
        subShelfViewportHeight = subHeight
        subShelfScrollHeight = activeHeight < ShelfLayout.naturalHeight(actions: subActions, submenu: true) ? max(0, activeHeight - shelfPaddingTop - shelfPaddingBottom) : nil
        let subY = shelf.frame.maxY - subHeight
        subShelfInteractiveFrame = NSRect(x: subX, y: shelf.frame.maxY - activeHeight, width: subWidth, height: activeHeight)
        
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
        
        let container = ActionSubShelfContainerView(presenter: self, subActions: subActions)
        if let host = subShelfHostingView {
            host.rootView = AnyView(container)
        } else {
            let host = NotificationHostingView(rootView: AnyView(container))
            subShelfHostingView = host
            subShelfWindow?.contentView = host
        }
        
        if let host = subShelfHostingView as? NotificationHostingView<AnyView> {
            host.isHitInNotificationBox = { point in point.y >= subHeight - activeHeight }
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
            Task { @MainActor in
                guard let self, self.subShelfCloseToken == closeToken else { return }
                subShelf.orderOut(nil)
                self.subShelfHostingView = nil
                self.subShelfInteractiveFrame = nil
                completion?()
            }
        }
    }
    
    private func closeSubShelfInstantly() {
        subShelfCloseToken = UUID()
        activeSubmenu = nil
        isHoveringSubShelf = false
        subShelfInteractiveFrame = nil
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
            let isOverSub = self.subShelfInteractiveFrame?.contains(mouseLoc) ?? false
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
        
        let generation = sessionGeneration
        let closeToken = UUID()
        shelfCloseToken = closeToken
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shelf.animator().alphaValue = 0
            self.subShelfWindow?.animator().alphaValue = 0
        }) { [weak self] in
            Task { @MainActor in
                guard let self, self.sessionGeneration == generation, self.shelfCloseToken == closeToken else { return }
                shelf.orderOut(nil)
                self.subShelfWindow?.orderOut(nil)
                self.shelfHostingView = nil
                self.subShelfHostingView = nil
                self.activeSubmenu = nil
                self.isHoveringSubShelf = false
                self.subShelfInteractiveFrame = nil
                completion?()
            }
        }
    }
    
    private func closeActionShelfInstantly() {
        shelfCloseToken = UUID()
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
    
    func invalidatePendingActions() {
        sessionGeneration = UUID()
        executionTask?.cancel()
        executionTask = nil
    }

    func dismissNotification(preservingSession: Bool = false) {
        if !preservingSession { invalidatePendingActions() }

        stopShelfLivenessTracking()
        stopKeyMonitoring()
        closeActionShelfInstantly()
        isShowingNotification = false
        dismissTimer?.cancel()
        dismissTimer = nil
        notificationWindow?.orderOut(nil)
        hostingView = nil
    }
    
    private func hideNotificationWithAnimation(preservingSession: Bool = false, completion: (() -> Void)? = nil) {
        if !preservingSession { invalidatePendingActions() }
        let generation = sessionGeneration
        cancelDismissTimer()
        stopShelfLivenessTracking()
        stopKeyMonitoring()
        isShowingNotification = false
        isShelfOpen = false
        let finish = { [weak self] in
            guard let self, self.sessionGeneration == generation else { return }
            self.dismissNotification(preservingSession: true)
            completion?()
        }
        if let animationScheduler {
            animationScheduler(finish)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.notificationWindow?.animator().alphaValue = 0
                self.shelfWindow?.animator().alphaValue = 0
                self.subShelfWindow?.animator().alphaValue = 0
            }, completionHandler: { Task { @MainActor in finish() } })
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
            let isOverSubShelf = self.activeSubmenu != nil && (self.subShelfInteractiveFrame?.contains(mouseLoc) ?? false)
            let isOverNotif = self.visibleNotificationBoxFrame?.contains(mouseLoc) ?? false
            
            let isOverAnyShelf = isOverMainShelf || isOverSubShelf
            self.isHoveringShelf = isOverMainShelf
            self.isHoveringSubShelf = isOverSubShelf
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
            guard let self = self, (self.isHoveringNotification || self.isHoveringShelf || self.isHoveringSubShelf), self.supportsQuickActions else {
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
                if let action = self.actionForShortcut(digit) {
                    self.triggerQuickAction(action)
                    return nil
                }
            }
            return event
        }
    }
    
    func actionForShortcut(_ digit: Int) -> QuickAction? {
        guard (1...9).contains(digit) else { return nil }
        let actions = activeSubmenu?.subActions ?? (activeSubmenu == nil ? quickActions : [])
        return actions.first { $0.shortcutNumber == digit }
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
        if action.operation == .submenu {
            openSubShelf(for: action)
            return
        }
        guard let context = currentActionContext, !context.text.isEmpty else { return }
        let config = configProvider()
        let screen = targetScreen
        let generation = sessionGeneration
        hideNotificationWithAnimation(preservingSession: true) { [weak self] in
            guard let self, self.sessionGeneration == generation else { return }
            self.executionTask?.cancel()
            self.executionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let result = try await self.actionExecutor.execute(action, context: context, config: config)
                    guard !Task.isCancelled, self.sessionGeneration == generation else { return }
                    switch result {
                    case .openURL(let url):
                        guard self.openURL(url) else { throw ActionExecutionError.invalidURL }
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        FeedbackManager.playSuccessSound()
                    case .copy(let updated, let subtitle):
                        self.copyText(updated.text)
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        FeedbackManager.playSuccessSound()
                        self.showNotification(title: "Quick Action: \(action.title)", subtitle: subtitle,
                                              body: TextPreview.format(updated.text, limit: SettingsManager.shared.textPreviewLimit),
                                              fullBody: updated.text, customIcon: action.icon, accentColor: .adaptiveGreen,
                                              targetScreen: screen, supportsQuickActions: true, actionContext: updated)
                    }
                } catch {
                    guard !Task.isCancelled, self.sessionGeneration == generation else { return }
                    self.showNotification(title: "Quick Action Failed", subtitle: action.title,
                                          body: error.localizedDescription, iconName: "exclamationmark.triangle.fill",
                                          accentColor: .orange, targetScreen: screen)
                }
            }
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
            viewportHeight: presenter.mainShelfScrollHeight,
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

private struct ActionSubShelfContainerView: View {
    @ObservedObject var presenter: NotificationPresenter
    let subActions: [QuickAction]
    
    var body: some View {
        ActionSubShelfView(
            subActions: subActions,
            accentColor: presenter.notificationAccentColor,
            viewportHeight: presenter.subShelfScrollHeight,
            isMainShelfHovered: presenter.isHoveringShelf,
            onActionSelected: { [weak presenter] selectedAction in
                presenter?.triggerQuickAction(selectedAction)
            },
            onHoverChange: { [weak presenter] hovering in
                presenter?.handleSubShelfHover(hovering)
            }
        )
        .frame(height: presenter.subShelfViewportHeight, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qa-submenu-content")
        .preferredColorScheme(SettingsManager.shared.appearance.colorScheme)
    }
}

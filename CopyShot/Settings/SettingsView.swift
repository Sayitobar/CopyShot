//
//  SettingsView.swift
//  CopyShot
//

import SwiftUI
import Sparkle

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case capture = "OCR & Capture"
    case notifications = "Notifications"
    case quickActions = "Quick Actions"
    case about = "About"
    
    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .capture: return "camera.viewfinder"
        case .notifications: return "bell"
        case .quickActions: return "rectangle.and.pencil.and.ellipsis"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Safe Slide Transition
// Using a custom ViewModifier prevents the offset from intrinsically altering 
// the layout bounds during the animation, preventing the window from bouncing.
struct SlideFadeModifier: ViewModifier {
    let offset: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offset)
    }
}

extension AnyTransition {
    static var slideFade: AnyTransition {
        let insertion = AnyTransition.modifier(
            active: SlideFadeModifier(offset: 15, opacity: 0),
            identity: SlideFadeModifier(offset: 0, opacity: 1)
        )
        // Disappear instantly without any movement or linear fade!
        let removal = AnyTransition.modifier(
            active: SlideFadeModifier(offset: 0, opacity: 0),
            identity: SlideFadeModifier(offset: 0, opacity: 1)
        ).animation(.linear(duration: 0))
        
        return .asymmetric(insertion: insertion, removal: removal)
    }
}

// MARK: - Native Window Dragging Area
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView {
        DragNSView()
    }
    func updateNSView(_ nsView: DragNSView, context: Context) {}

    class DragNSView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            return true
        }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

struct SettingsHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 68
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

struct SettingsContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

struct ViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

struct LiveContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

// MARK: - Settings Window Manager
@MainActor
final class SettingsWindowManager: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()
    
    private var window: NSWindow?
    private var updaterViewModel: UpdaterViewModel?
    private var localKeyMonitor: Any?
    
    func showSettings(updaterViewModel: UpdaterViewModel? = nil) {
        if let updater = updaterViewModel {
            self.updaterViewModel = updater
        }
        
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
        
        if let existingWindow = self.window {
            if let screen = targetScreen {
                let currentScreen = existingWindow.screen
                if currentScreen != screen || !existingWindow.isVisible {
                    let screenRect = screen.visibleFrame
                    let windowRect = existingWindow.frame
                    let x = screenRect.origin.x + (screenRect.width - windowRect.width) / 2
                    let y = screenRect.origin.y + (screenRect.height - windowRect.height) / 2
                    existingWindow.setFrameOrigin(NSPoint(x: x, y: y))
                }
            }
            updateAppearance()
            setupKeyMonitorIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        createAndShowWindow(on: targetScreen)
    }
    
    private func createAndShowWindow(on targetScreen: NSScreen?) {
        let settingsView = SettingsView()
            .environmentObject(SettingsManager.shared)
            .environmentObject(updaterViewModel ?? UpdaterViewModel())
        
        let hostingController = NSHostingController(rootView: settingsView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Settings"
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.isMovableByWindowBackground = false
        newWindow.toolbar = nil
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.standardWindowButton(.closeButton)?.isHidden = true
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newWindow.standardWindowButton(.zoomButton)?.isHidden = true
        newWindow.isReleasedWhenClosed = false
        if #available(macOS 11.0, *) {
            newWindow.titlebarSeparatorStyle = .none
        }
        
        newWindow.contentViewController = hostingController
        newWindow.delegate = self
        self.window = newWindow
        
        updateAppearance()
        setupKeyMonitorIfNeeded()
        
        if let screen = targetScreen {
            let screenRect = screen.visibleFrame
            let windowRect = newWindow.frame
            let x = screenRect.origin.x + (screenRect.width - windowRect.width) / 2
            let y = screenRect.origin.y + (screenRect.height - windowRect.height) / 2
            newWindow.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            newWindow.center()
        }
        
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }
    
    func closeSettings() {
        removeKeyMonitor()
        window?.close()
    }
    
    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
    }
    
    // MARK: - Debug Overlay Keyboard Monitor (⇧⌥⌘D only when Settings is open)
    
    private func setupKeyMonitorIfNeeded() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let window = self.window, event.window == window else {
                return event
            }
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command, .option, .shift],
               event.charactersIgnoringModifiers?.lowercased() == "d" {
                SettingsManager.shared.showDebugOverlay.toggle()
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                return nil // Swallow event
            }
            return event
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
    
    func updateAppearance() {
        guard let window = self.window else { return }
        switch SettingsManager.shared.appearance {
        case .light: window.appearance = NSAppearance(named: .aqua)
        case .dark: window.appearance = NSAppearance(named: .darkAqua)
        case .system: window.appearance = nil
        }
    }
    
    var currentScreen: NSScreen? {
        return window?.screen ?? NSScreen.main
    }
    
    func updateWindowHeight(_ newHeight: CGFloat) {
        guard let window = self.window else { return }
        let currentFrame = window.frame
        
        let screen = window.screen ?? NSScreen.main
        let maxScreenHeight = max((screen?.visibleFrame.height ?? 800) - 80, 300)
        let targetHeight = min(newHeight, maxScreenHeight)
        
        if abs(currentFrame.height - targetHeight) < 1 { return }
        
        let topY = currentFrame.origin.y + currentFrame.size.height
        let newOriginY = topY - targetHeight
        let newFrame = NSRect(x: currentFrame.origin.x, y: newOriginY, width: currentFrame.width, height: targetHeight)
        
        if !window.isVisible {
            window.setFrame(newFrame, display: true)
            return
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0)
            window.animator().setFrame(newFrame, display: true)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @State private var layoutTab: SettingsTab = .general
    @State private var visibleTab: SettingsTab = .general
    @State private var isTransitioning = false
    @State private var headerHeight: CGFloat = 68
    @State private var contentHeight: CGFloat = 0
    @State private var liveContentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme
    
    // Toggle content transitions ON/OFF (Slide under tab bar)
    // Does NOT restrict the tab button highlighter slide.
    private let enableContentAnimations = true
    
    @ViewBuilder
    private func tabContentView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsView()
        case .capture: CaptureSettingsView()
        case .notifications: NotificationsSettingsView()
        case .quickActions: QuickActionsSettingsView()
        case .about: AboutSettingsView(updaterViewModel: updaterViewModel)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. TAB BAR HEADER (ZIndex 2 so it physically overlays the rendering stack)
            VStack(spacing: 0) {
                HStack(spacing: TabButton.tabSpacing) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        TabButton(tab: tab, isSelected: visibleTab == tab, isTransitioning: isTransitioning) {
                            if visibleTab == tab { return }
                            isTransitioning = true
                            layoutTab = tab
                            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)) {
                                visibleTab = tab
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                isTransitioning = false
                            }
                        }
                        .debugZone(tab.rawValue, type: .interactive)
                    }
                }
                .background(alignment: .leading) {
                    let index = CGFloat(SettingsTab.allCases.firstIndex(of: visibleTab) ?? 0)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(colorScheme == .dark ? Color(red: 70/255, green: 70/255, blue: 70/255) : Color(red: 226/255, green: 226/255, blue: 226/255))
                        .shadow(color: .clear, radius: 0)
                        .frame(width: TabButton.tabWidth, height: TabButton.tabHeight)
                        .offset(x: index * (TabButton.tabWidth + TabButton.tabSpacing))
                }
                .padding(.top, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                
                Divider() // Separates our Tab Bar from our Content
                    .opacity(0.5)
            }
            .debugZone("Header Bar", type: .windowBoundary)
            .background(WindowDragArea())
            .overlay(alignment: .topLeading) {
                // BESPOKE CUSTOM CLOSE BUTTON
                CustomCloseButton()
                    .debugZone("Close", type: .interactive)
                    .padding(.top, 16)
                    .padding(.leading, 18)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: SettingsHeaderHeightKey.self, value: geo.size.height)
                }
            )
            .zIndex(2)
            
            // 2. CONTENT AREA
            ZStack(alignment: .top) {
                ScrollView(.vertical, showsIndicators: isScrollNeeded) {
                    ZStack(alignment: .top) {
                        let activeTransition = enableContentAnimations ? AnyTransition.slideFade : .identity
                        tabContentView(for: visibleTab)
                            .transition(activeTransition)
                    }
                    .padding(.vertical, 32)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: LiveContentHeightKey.self, value: geo.size.height)
                        }
                    )
                }
                .scrollDisabled(!isScrollNeeded)
                
                // Linear Gradient Shadow that behaves exclusively as an internal under-lay, drawing on top of scrolled content!
                LinearGradient(
                    colors: [Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 6)
                .allowsHitTesting(false)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ViewportHeightKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(ViewportHeightKey.self) { newViewportHeight in
                if newViewportHeight > 0 {
                    viewportHeight = newViewportHeight
                }
            }
            .debugZone("Content Area", type: .windowBoundary)
            .clipped()
            .zIndex(1)
        }
        .overlay(alignment: .bottom) {
            if settings.showDebugOverlay {
                Text("Debug Zones Active (⇧⌥⌘D)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
        }
        // Shunts content UP into the transparent titlebar void to align tabs on the traffic light row.
        // Tuned for macOS 15 titlebar geometry (28pt height). If future macOS versions alter titlebar height, adjust here.
        .padding(.top, -28)
        .frame(minWidth: 540, maxWidth: 540, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor).ignoresSafeArea())
        .background(
            // DYNAMIC CONTENT SIZING PROBE (measures natural height of layoutTab completely detached from visible layout)
            tabContentView(for: layoutTab)
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: SettingsContentHeightKey.self, value: geo.size.height)
                    }
                )
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true),
            alignment: .top
        )
        .preferredColorScheme(settings.appearance.colorScheme)
        .id(settings.appearance)
        .onChange(of: settings.appearance) { _ in
            SettingsWindowManager.shared.updateAppearance()
        }
        .onPreferenceChange(SettingsHeaderHeightKey.self) { newHeaderHeight in
            if newHeaderHeight > 0 {
                headerHeight = newHeaderHeight
                updateTotalHeight()
            }
        }
        .onPreferenceChange(SettingsContentHeightKey.self) { newContentHeight in
            if newContentHeight > 0 {
                contentHeight = newContentHeight
                updateTotalHeight()
            }
        }
        .onPreferenceChange(LiveContentHeightKey.self) { newLiveHeight in
            if newLiveHeight > 0 {
                liveContentHeight = newLiveHeight
            }
        }
    }
    
    private var isScrollNeeded: Bool {
        guard viewportHeight > 50 else { return false }
        return liveContentHeight > (viewportHeight + 2)
    }
    
    private func updateTotalHeight() {
        let total = headerHeight + contentHeight
        if total > 50 {
            SettingsWindowManager.shared.updateWindowHeight(total)
        }
    }
}

// MARK: - Custom Tab Button
struct TabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let isTransitioning: Bool
    let action: () -> Void
    
    static let tabWidth: CGFloat = 84
    static let tabHeight: CGFloat = 46
    static let tabSpacing: CGFloat = 6
    
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            isHovered = false
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .blue : (isHovered && !isTransitioning ? .primary : .secondary))
                    .animation(nil, value: isSelected) // Instant color swap, no interpolation during slide
                    .frame(height: 18)
                
                Text(tab.rawValue)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : (isHovered && !isTransitioning ? .primary : .secondary))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.85)
                    .animation(nil, value: isSelected) // Instant color swap, no interpolation during slide
                    .frame(height: 14)
            }
            .frame(width: Self.tabWidth, height: Self.tabHeight)
            .contentShape(Rectangle()) // Ensures dead-space is clickable
            .background(
                Group {
                    if isHovered && !isSelected && !isTransitioning {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.05))
                    }
                }
            )
            .animation(nil, value: isSelected)
            .animation(nil, value: isTransitioning)
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            if isTransitioning || isSelected {
                isHovered = false
            } else {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hovered
                }
            }
        }
    }
}

// MARK: - Custom Close Button
struct CustomCloseButton: View {
    @State private var isHovered = false
    @Environment(\.controlActiveState) var controlActiveState
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let isActive = controlActiveState != .inactive
        let activeColor = isHovered ? Color(red: 255/255, green: 80/255, blue: 75/255) : Color(red: 255/255, green: 95/255, blue: 86/255)
        
        Button(action: {
            SettingsWindowManager.shared.closeSettings()
        }) {
            Circle()
                .fill(isActive ? activeColor : Color(white: colorScheme == .dark ? 0.3 : 0.8))
                .frame(width: 12, height: 12)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .offset(x: 0.25, y: 0) // Nudge slightly right to perfectly center
                        .opacity(isHovered && isActive ? 1 : 0)
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(isActive ? 0.12 : 0.05), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovered
            }
        }
    }
}

// MARK: - Base Settings Row
struct SettingsRow<Control: View>: View {
    let label: String
    let tooltip: String?
    let zIndexValue: Double
    @ViewBuilder let control: () -> Control
    
    @State private var tooltipHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Right-aligned label column (fixed width)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 140, alignment: .leading)
                .padding(.top, 3) // Nudge down slightly so text aligns with the middle of controls like Toggles or Buttons
            
            // Right-aligned control column (fixed width)
            control()
                .frame(width: 200, alignment: .trailing)
            
            // Tooltip column (fixed width)
            if let tooltip = tooltip {
                InfoTooltip(text: tooltip, onHoverStateChange: { hovered in
                    tooltipHovered = hovered
                })
                .frame(width: 18, alignment: .leading)
            } else {
                Spacer().frame(width: 18) // Placeholder for alignment
            }
        }
        .frame(maxWidth: .infinity) // Center the fixed-width group in the window
        .zIndex(tooltipHovered ? 1000 : zIndexValue) // Elevates row priority wildly when hovering tooltip
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            SettingsRow(label: "Launch at Login", tooltip: "Automatically start CopyShot when you log in to your Mac.", zIndexValue: 10) {
                Toggle("", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            SettingsRow(label: "Auto Update", tooltip: "Automatically check for new versions once a day in the background.", zIndexValue: 9) {
                Toggle("", isOn: $updaterViewModel.automaticallyChecksForUpdates)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            SettingsRow(label: "Appearance", tooltip: "Choose between Light, Dark, or System appearance.", zIndexValue: 8) {
                Picker("", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.rawValue).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200) // Fixed width for uniformity
            }
        }
    }
}

// MARK: - Capture Settings
struct CaptureSettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    
    private var availableLanguages: [String] {
        settings.supportedLanguages.filter { !settings.recognitionLanguages.contains($0) }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            SettingsRow(label: "Capture Screenshot", tooltip: "Global hotkey to trigger screen capture.", zIndexValue: 11) {
                VStack(alignment: .leading, spacing: 6) {
                    HotkeyField(hotkey: $settings.captureHotkey, placeholder: "Click to set")
                        .frame(width: 200) // Match width of picker above
                    
                    Button("Reset Hotkey to Default") {
                        settings.resetHotkeysToDefaults()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .font(.system(size: 11))
                    .padding(.leading, 2) // slight optical alignment
                }
            }
            
            SettingsRow(label: "Recognition Level", tooltip: "Fast: Character detection & small ML model.\nAccurate: Neural network for human-like string & line recognition.", zIndexValue: 10) {
                Picker("", selection: $settings.recognitionLevel) {
                    ForEach(RecognitionLevel.allCases) { level in
                        Text(level.description).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200) // Fixed to be consistent width
            }
            
            SettingsRow(label: "Language Correction", tooltip: "Applies Natural Language Processing (NLP) to minimize misreadings.\nNote: Not supported for Chinese. Disable this for code or technical symbols.", zIndexValue: 9) {
                Toggle("", isOn: $settings.usesLanguageCorrection)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            SettingsRow(label: "Add Language", tooltip: "Add languages to improve recognition accuracy for mixed content.", zIndexValue: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    Menu {
                        ForEach(availableLanguages, id: \.self) { language in
                            Button(action: {
                                addLanguage(language)
                            }) {
                                Text(Locale.current.localizedString(forIdentifier: language) ?? language)
                            }
                        }
                    } label: {
                        HStack {
                            Text(availableLanguages.isEmpty ? "All added" : "Add Language...")
                                .foregroundStyle(availableLanguages.isEmpty ? .secondary : .primary)
                                .font(.system(size: 12))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .frame(width: 200) // Match width of picker
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(.rect(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(availableLanguages.isEmpty)
                    
                    if !settings.recognitionLanguages.isEmpty {
                        // Collective Box for added languages
                        ScrollView(.vertical, showsIndicators: settings.recognitionLanguages.count > 3) {
                            VStack(spacing: 0) {
                                ForEach(Array(settings.recognitionLanguages.enumerated()), id: \.element) { index, language in
                                    LanguageRow(
                                        language: language,
                                        canRemove: settings.recognitionLanguages.count > 1,
                                        isLast: index == settings.recognitionLanguages.count - 1
                                    ) {
                                        removeLanguage(language)
                                    }
                                }
                            }
                        }
                        .frame(width: 200) // Match width of container
                        .frame(maxHeight: 110)
                        .background(Color(.controlBackgroundColor).opacity(0.5))
                        .clipShape(.rect(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .onAppear {
            if settings.recognitionLanguages.isEmpty {
                settings.recognitionLanguages = ["en-US"]
            }
        }
    }
    
    private func addLanguage(_ language: String) {
        if !settings.recognitionLanguages.contains(language) {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)) {
                settings.recognitionLanguages.append(language)
            }
        }
    }
    
    private func removeLanguage(_ language: String) {
        if settings.recognitionLanguages.count > 1 {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)) {
                settings.recognitionLanguages.removeAll { $0 == language }
            }
        }
    }
}

// MARK: - Notifications Settings
struct NotificationsSettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        VStack(spacing: 24) {
            SettingsRow(label: "Play Sounds", tooltip: "Play a sound when a capture succeeds or fails.", zIndexValue: 10) {
                Toggle("", isOn: $settings.playNotificationSound)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            SettingsRow(label: "Text Preview Limit", tooltip: "Maximum characters to show in the notification.\nSet to 0 for full text.", zIndexValue: 9) {
                TextField("0", value: $settings.textPreviewLimit, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - About Settings
struct AboutSettingsView: View {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    @ObservedObject var updaterViewModel: UpdaterViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 26) {
                // App Logo
                if let appIcon = NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue.gradient)
                }
                
                // App Name, Version, and Copyright aligned left
                VStack(alignment: .leading, spacing: 4) {
                    Text("CopyShot")
                        .font(.system(size: 32, weight: .bold))
                        .padding(.bottom, 2)
                    
                    Text("Version \(appVersion)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    
                    Text(verbatim: "Sayitobar, \(Calendar.current.component(.year, from: Date()))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .padding(.leading, -10)
            }
            .padding(.horizontal) // Keeps the top section from touching the very edge of the window
            .padding(.bottom, 32)

            // Divider now stretches indefinitely
            Divider()
                .padding(.horizontal, -30)
                .padding(.bottom, 10)
            
            // All four buttons in a single row — icon-only, expand on hover
            HStack(spacing: 10) {
                // Local file openers (left)
                AboutButton(title: "Show in Finder", icon: "app.badge") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                
                AboutButton(title: "App Data Folder", icon: "folder") {
                    let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    let appDir = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "CopyShot")
                    try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDir.path)
                }
                
                Spacer()
                
                // Online buttons (right)
                AboutButton(title: "Check Updates", icon: "arrow.triangle.2.circlepath") {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)
                
                if let url = URL(string: "https://github.com/Sayitobar/CopyShot") {
                    AboutButton(title: "Source Code", icon: "link") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(.horizontal, -12)  // move buttons closer to the side walls to leave a 10px gap
            .padding(.bottom, -22)  // move buttons closer to the bottom wall to leave a 10px gap
        }
        .frame(maxWidth: .infinity)
    }
}

struct AboutButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: isHovered ? 6 : 0) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(.blue)
                    .font(.system(size: 13, weight: .medium))
                
                if isHovered {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .padding(.horizontal, isHovered ? 12 : 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: colorScheme == .dark ? 0.25 : 0.85).opacity(isHovered ? 1.0 : 0.7))
            )
            .opacity(isEnabled ? 1.0 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovered
            }
        }
    }
}


// MARK: - Hover Info Tooltip
struct InfoTooltip: View {
    let text: String
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    var onHoverStateChange: ((Bool) -> Void)? = nil
    
    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 14))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(4)
            .contentShape(Rectangle()) // makes the padding area hoverable
            .onHover { hovered in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovered
                }
                onHoverStateChange?(hovered)
            }
            .popover(isPresented: $isHovered, arrowEdge: .leading) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .padding(14)
                    .frame(width: 200, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }
}

// MARK: - Reusable Components
struct HotkeyField: View {
    @Binding var hotkey: HotkeyConfig
    let placeholder: String
    @State private var isCapturing = false
    @State private var eventMonitor: Any?
    
    var body: some View {
        Button(action: {
            if isCapturing {
                stopCapturing()
            } else {
                startCapturing()
            }
        }) {
            HStack {
                Spacer()
                Text(isCapturing ? "Press keys..." : hotkey.displayString)
                    .foregroundStyle(isCapturing ? .orange : .primary)
                    .font(.system(size: 13, weight: .medium))
                    .monospaced()
                Spacer()
                
                if isCapturing {
                    Button("Cancel") {
                        stopCapturing()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isCapturing ? Color.orange : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isCapturing ? Color.orange : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func startCapturing() {
        isCapturing = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            updateHotkey(with: event)
            return nil
        }
    }
    
    private func stopCapturing() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isCapturing = false
    }
    
    private func updateHotkey(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonModifiers = SettingsManager.carbonModifierFlags(from: modifiers)
        
        let newHotkey = HotkeyConfig(
            keyCode: event.keyCode,
            modifierFlags: carbonModifiers,
            displayString: SettingsManager.displayString(for: event.keyCode, modifierFlags: carbonModifiers)
        )
        
        if !SettingsManager.shared.isHotkeyInUse(newHotkey) {
            hotkey = newHotkey
            NotificationCenter.default.post(name: NSNotification.Name("HotkeySettingsChanged"), object: nil)
        }
        
        stopCapturing()
    }
}

struct LanguageRow: View {
    let language: String
    let canRemove: Bool
    let isLast: Bool
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Locale.current.localizedString(forIdentifier: language) ?? language)
                    .font(.system(size: 13))
                
                Spacer()
                
                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .opacity(0.5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            
            if !isLast {
                Divider()
                    .padding(.leading, 10)
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsManager.shared)
            .environmentObject(UpdaterViewModel())
    }
}
